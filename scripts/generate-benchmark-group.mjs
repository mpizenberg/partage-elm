// Generate a synthetic Partage group as an importable .partage file, for
// benchmarking large event logs on real devices.
//
//   node scripts/generate-benchmark-group.mjs [eventCount] [outFile]
//
// Defaults: 10000 events, partage-benchmark-<eventCount>.partage in the
// current directory. Every envelope is genuinely signed (ECDSA P-256 over
// the same canonical form the app verifies), so the import signature check
// and the diagnostics page's verification timing both exercise the real
// code path. The script re-verifies every signature before writing.
//
// To benchmark: import the file from the home page, enable developer mode
// on the About page, then open /groups/<groupId>/diagnostics (the group id
// is printed below; the settings-page button is only shown to members, and
// you are not a member of the synthetic group). Opening the group while
// online registers its id on the relay as an empty group — harmless, no
// event is ever pushed, and it expires with relay retention.

import { webcrypto as crypto } from "node:crypto";
import { gzipSync } from "node:zlib";
import { writeFileSync } from "node:fs";

const eventCount = Number(process.argv[2] ?? 10000);
if (!Number.isInteger(eventCount) || eventCount < 10 || eventCount > 200000) {
  console.error("eventCount must be an integer between 10 and 200000");
  process.exit(1);
}
const outFile = process.argv[3] ?? `partage-benchmark-${eventCount}.partage`;

// Deterministic mix (keys and ids still vary per run).
let prngState = 42;
function rand() {
  prngState |= 0;
  prngState = (prngState + 0x6d2b79f5) | 0;
  let t = Math.imul(prngState ^ (prngState >>> 15), 1 | prngState);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (list) => list[Math.floor(rand() * list.length)];
const randInt = (min, max) => min + Math.floor(rand() * (max - min + 1));

function uuidV7(tsMillis) {
  const bytes = new Uint8Array(16);
  const ts = BigInt(tsMillis);
  for (let i = 0; i < 6; i++) {
    bytes[i] = Number((ts >> BigInt(8 * (5 - i))) & 0xffn);
  }
  for (let i = 6; i < 16; i++) bytes[i] = randInt(0, 255);
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const toBase64 = (bytes) => Buffer.from(bytes).toString("base64");
const utf8 = (s) => new TextEncoder().encode(s);

async function makeRealMember(name) {
  const kp = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const publicKey = JSON.stringify(
    await crypto.subtle.exportKey("jwk", kp.publicKey),
  );
  const hash = await crypto.subtle.digest("SHA-256", utf8(publicKey));
  const id = [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return { id, name, publicKey, privateKey: kp.privateKey };
}

async function signEnvelope(member, envelopeWithoutSig) {
  const canonical = JSON.stringify(envelopeWithoutSig);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    member.privateKey,
    utf8(canonical),
  );
  return { ...envelopeWithoutSig, sig: toBase64(new Uint8Array(sig)) };
}

// --- Members ---

const realMembers = [];
for (const name of ["Alice", "Bruno", "Chloe", "David"]) {
  realMembers.push(await makeRealMember(name));
}
const creator = realMembers[0];
const virtualMembers = [
  { id: crypto.randomUUID(), name: "Emma" },
  { id: crypto.randomUUID(), name: "Felix" },
];
const allMemberIds = [...realMembers, ...virtualMembers].map((m) => m.id);

// --- Event stream ---

const dayMs = 24 * 3600 * 1000;
const startTs = Date.now() - 730 * dayMs;
const stepMs = Math.max(1, Math.floor((729 * dayMs) / eventCount));

const events = [];
const histogram = {};
let ts = startTs;

async function addEvent(author, payload, { key } = {}) {
  ts += randInt(1, stepMs);
  const envelope = { id: uuidV7(ts), ts, by: author.id, v: 1 };
  if (key) envelope.key = author.publicKey;
  envelope.p = payload;
  events.push(await signEnvelope(author, envelope));
  histogram[payload.t] = (histogram[payload.t] ?? 0) + 1;
}

function dateOf(tsMillis) {
  const d = new Date(tsMillis);
  return { y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, dy: d.getUTCDate() };
}

function expenseData(author) {
  const beneficiaries = [...allMemberIds]
    .sort(() => rand() - 0.5)
    .slice(0, randInt(2, allMemberIds.length))
    .map((m) => ({ t: "share", m, s: 1 }));
  const amount = randInt(300, 18000);
  const data = {
    desc: `${pick(["Groceries", "Restaurant", "Taxi", "Museum", "Drinks", "Bakery", "Fuel", "Tickets", "Pharmacy", "Market"])} ${pick(["run", "night", "stop", "visit", "trip"])}`,
    a: amount,
    cur: "eur",
    dt: dateOf(ts),
    pay: [{ m: author.id, a: amount }],
    ben: beneficiaries,
  };
  if (rand() < 0.7) {
    data.cat = pick([
      "food",
      "transport",
      "accommodation",
      "entertainment",
      "shopping",
      "groceries",
      "utilities",
      "healthcare",
      "other",
    ]);
  }
  if (rand() < 0.1) data.loc = pick(["Lyon", "Paris", "Grenoble", "Annecy"]);
  if (rand() < 0.15) data.nt = "Split evenly as usual";
  return data;
}

// Bootstrap: GroupCreated, then each real member self-introducing (with
// their signing key on the envelope), then virtual members added by the
// creator.
const idChars = "abcdefghijklmnopqrstuvwxyz0123456789";
const groupId =
  "bench" +
  Array.from(crypto.getRandomValues(new Uint8Array(10)), (b) =>
    idChars.charAt(b % idChars.length),
  ).join("");
const groupName = `Benchmark ${eventCount}`;

await addEvent(creator, { t: "gc", n: groupName, dc: "eur" });
for (const member of realMembers) {
  await addEvent(
    member,
    { t: "mc", m: member.id, n: member.name, mt: "real", ab: creator.id },
    { key: true },
  );
}
for (const member of virtualMembers) {
  await addEvent(creator, {
    t: "mc",
    m: member.id,
    n: member.name,
    mt: "virtual",
    ab: creator.id,
  });
}

// Main mix, roughly matching real usage: mostly new expenses, some edits,
// a few transfers, deletions, and member/metadata churn.
const liveEntries = [];
while (events.length < eventCount) {
  const author = pick(realMembers);
  const roll = rand();
  if (roll < 0.83 || liveEntries.length === 0) {
    const entryId = uuidV7(ts + 1);
    const meta = {
      id: entryId,
      r: entryId,
      dp: 0,
      del: false,
      cb: author.id,
      ca: ts + 1,
    };
    if (roll >= 0.76 && roll < 0.83) {
      const [from, to] = [...allMemberIds].sort(() => rand() - 0.5);
      await addEvent(author, {
        t: "ea",
        e: {
          m: meta,
          k: {
            t: "transfer",
            d: { a: randInt(500, 10000), cur: "eur", dt: dateOf(ts), f: from, to },
          },
        },
      });
    } else {
      await addEvent(author, {
        t: "ea",
        e: { m: meta, k: { t: "expense", d: expenseData(author) } },
      });
    }
    liveEntries.push(meta);
  } else if (roll < 0.93) {
    const prev = pick(liveEntries);
    const newId = uuidV7(ts + 1);
    const meta = { ...prev, id: newId, dp: prev.dp + 1, pv: prev.id };
    await addEvent(author, {
      t: "em",
      e: { m: meta, k: { t: "expense", d: expenseData(author) } },
    });
    liveEntries[liveEntries.indexOf(prev)] = meta;
  } else if (roll < 0.96) {
    const victim = liveEntries.splice(randInt(0, liveEntries.length - 1), 1)[0];
    await addEvent(author, { t: "ed", r: victim.r });
  } else if (roll < 0.98) {
    await addEvent(author, {
      t: "mr",
      r: author.id,
      on: author.name,
      nn: `${author.name} ${pick(["B.", "C.", "D.", "M."])}`,
    });
  } else {
    await addEvent(author, {
      t: "spu",
      mr: author.id,
      pr: [pick(allMemberIds)],
    });
  }
}

// --- Self-verification: replay the app's canonicalize + verify logic ---

const json = JSON.stringify({
  format: "partage-group-v1",
  exportedAt: Date.now(),
  group: {
    id: groupId,
    n: groupName,
    dc: "eur",
    sub: false,
    ar: false,
    ca: startTs,
    mc: allMemberIds.length,
    mb: 0,
  },
  groupKey: toBase64(crypto.getRandomValues(new Uint8Array(32))),
  events,
});

const reparsed = JSON.parse(json);
const keyByMember = {};
for (const env of reparsed.events) {
  if (env.key && !(env.by in keyByMember)) keyByMember[env.by] = env.key;
}
let verified = 0;
for (const env of reparsed.events) {
  if (env.p.t === "gc") continue; // genesis events are exempt in the app too
  const { sig, ...unsigned } = env;
  const pubKey = await crypto.subtle.importKey(
    "jwk",
    JSON.parse(keyByMember[env.by]),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pubKey,
    Buffer.from(sig, "base64"),
    utf8(JSON.stringify(unsigned)),
  );
  if (!ok) {
    console.error(`Signature verification failed for event ${env.id}`);
    process.exit(1);
  }
  verified += 1;
}

const compressed = gzipSync(Buffer.from(json));
writeFileSync(outFile, compressed);

console.log(`Wrote ${outFile}`);
console.log(`  group id:   ${groupId}`);
console.log(`  events:     ${events.length} (${verified} signatures verified)`);
console.log(
  `  mix:        ${Object.entries(histogram)
    .sort((a, b) => b[1] - a[1])
    .map(([t, n]) => `${t}:${n}`)
    .join(" ")}`,
);
console.log(`  plaintext:  ${(json.length / 1e6).toFixed(2)} MB`);
console.log(`  file size:  ${(compressed.length / 1e6).toFixed(2)} MB`);
console.log(`
Import the file from the home page, enable developer mode on the About
page, then open /groups/${groupId}/diagnostics`);
