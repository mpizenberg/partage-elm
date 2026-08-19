import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeApp,
  createGroup,
  pushEvent,
  pullEvents,
  compactGroup,
  record,
  solvedPow,
  sha256Base64Url,
} from '../test-support/helpers.js';

const GENEROUS = { maxRecords: 50000, maxTotalBytes: 50 * 1024 * 1024, rateBytes: 10 * 1024 * 1024, windowMs: 1000 };

let nextGroup = 0;
const uid = () => `g${nextGroup++}`;

describe('group creation', () => {
  it('creates a group with a valid PoW solution', async () => {
    const app = makeApp().app;
    const { res } = await createGroup(app, { groupId: uid() });
    assert.equal(res.status, 201);
  });

  it('rejects creation without PoW', async () => {
    const app = makeApp().app;
    const res = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        groupId: uid(),
        createdBy: 'creator',
        authVerifier: sha256Base64Url('secret'),
      }),
    });
    assert.equal(res.status, 400);
  });

  it('rejects a challenge request without a groupId', async () => {
    const app = makeApp().app;
    const res = await app.request('/api/pow/challenge');
    assert.equal(res.status, 400);
  });

  it('rejects a challenge reused for another group', async () => {
    const app = makeApp().app;
    const solvedFor = uid();
    const pow = await solvedPow(app, solvedFor);
    const body = (groupId) => ({
      groupId,
      createdBy: 'creator',
      authVerifier: sha256Base64Url('secret'),
      ...pow,
    });
    const first = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body(solvedFor)),
    });
    assert.equal(first.status, 201);
    const second = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body(uid())),
    });
    assert.equal(second.status, 400);
    assert.match((await second.json()).error, /Invalid challenge signature/);
  });

  it('rejects a duplicate groupId', async () => {
    const app = makeApp().app;
    const groupId = uid();
    await createGroup(app, { groupId });
    const { res } = await createGroup(app, { groupId });
    assert.equal(res.status, 409);
    assert.match((await res.json()).error, /already exists/);
  });
});

describe('events auth', () => {
  it('rejects requests without a bearer token', async () => {
    const app = makeApp().app;
    const { groupId } = await createGroup(app, { groupId: uid() });
    const res = await app.request(`/api/groups/${groupId}/events`);
    assert.equal(res.status, 401);
  });

  it('rejects a wrong secret', async () => {
    const app = makeApp().app;
    const { groupId } = await createGroup(app, { groupId: uid() });
    const res = await pullEvents(app, groupId, 'wrong-secret');
    assert.equal(res.status, 401);
  });

  it('returns 404 for an unknown group', async () => {
    const app = makeApp().app;
    const res = await pullEvents(app, 'nope', 'any-secret');
    assert.equal(res.status, 404);
  });

  it("rejects one group's secret on another group", async () => {
    const app = makeApp().app;
    const a = await createGroup(app, { groupId: uid() });
    const b = await createGroup(app, { groupId: uid() });
    const res = await pullEvents(app, b.groupId, a.secret);
    assert.equal(res.status, 401);
  });
});

describe('event push and pull', () => {
  it('appends events with increasing seq and pulls from a cursor', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });

    const seqs = [];
    for (let i = 1; i <= 3; i++) {
      const res = await pushEvent(app, groupId, secret, { eventData: `blob-${i}` });
      assert.equal(res.status, 201);
      seqs.push((await res.json()).seq);
    }
    assert.ok(seqs[0] < seqs[1] && seqs[1] < seqs[2]);

    const all = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(all.hasMore, false);
    assert.deepEqual(
      all.events.map((e) => [e.seq, e.eventData]),
      [[seqs[0], 'blob-1'], [seqs[1], 'blob-2'], [seqs[2], 'blob-3']],
    );

    const tail = await (await pullEvents(app, groupId, secret, seqs[1])).json();
    assert.deepEqual(tail.events.map((e) => e.seq), [seqs[2]]);
  });

  it('scopes events to their group', async () => {
    const app = makeApp().app;
    const a = await createGroup(app, { groupId: uid() });
    const b = await createGroup(app, { groupId: uid() });
    await pushEvent(app, a.groupId, a.secret, { eventData: 'from-a' });
    const pulled = await (await pullEvents(app, b.groupId, b.secret)).json();
    assert.deepEqual(pulled.events, []);
  });

  it('paginates pulls at 200 events', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    for (let i = 0; i < 201; i++) {
      await pushEvent(app, groupId, secret, { eventData: `blob-${i}` });
    }

    const first = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(first.events.length, 200);
    assert.equal(first.hasMore, true);

    const cursor = first.events.at(-1).seq;
    const second = await (await pullEvents(app, groupId, secret, cursor)).json();
    assert.equal(second.events.length, 1);
    assert.equal(second.hasMore, false);
  });

  it('rejects an eventData blob over 1 MB', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const res = await pushEvent(app, groupId, secret, {
      eventData: 'x'.repeat(1024 * 1024 + 1),
    });
    assert.equal(res.status, 413);
  });

  it('replaying a recordId returns the original seq without inserting', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const first = await (await pushEvent(app, groupId, secret, { recordId: 'batch-1' })).json();
    const replay = await (
      await pushEvent(app, groupId, secret, { recordId: 'batch-1', eventData: 'other-blob' })
    ).json();
    assert.equal(replay.seq, first.seq);
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(pulled.events.length, 1);
  });

  it('scopes recordId dedup to the group and skips it when absent', async () => {
    const app = makeApp().app;
    const a = await createGroup(app, { groupId: uid() });
    const b = await createGroup(app, { groupId: uid() });
    await pushEvent(app, a.groupId, a.secret, { recordId: 'shared' });
    await pushEvent(app, b.groupId, b.secret, { recordId: 'shared' });
    const pulledB = await (await pullEvents(app, b.groupId, b.secret)).json();
    assert.equal(pulledB.events.length, 1);

    await pushEvent(app, a.groupId, a.secret, {});
    await pushEvent(app, a.groupId, a.secret, {});
    const pulledA = await (await pullEvents(app, a.groupId, a.secret)).json();
    assert.equal(pulledA.events.length, 3);
  });

  it('rejects a malformed recordId', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const empty = await pushEvent(app, groupId, secret, { recordId: '' });
    assert.equal(empty.status, 400);
    const long = await pushEvent(app, groupId, secret, { recordId: 'x'.repeat(201) });
    assert.equal(long.status, 400);
  });

  it('asks for a cursor reset when since is beyond the group history', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seq = (await (await pushEvent(app, groupId, secret)).json()).seq;
    const pulled = await (await pullEvents(app, groupId, secret, seq + 10)).json();
    assert.deepEqual(pulled, { events: [], hasMore: false, recordCount: 1, groupEpoch: pulled.groupEpoch, resetCursor: true });
    assert.equal(typeof pulled.groupEpoch, 'string');
  });

  it('asks for a cursor reset when the group has no events but since > 0', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const pulled = await (await pullEvents(app, groupId, secret, 5)).json();
    assert.deepEqual(pulled, { events: [], hasMore: false, recordCount: 0, groupEpoch: pulled.groupEpoch, resetCursor: true });
    assert.equal(typeof pulled.groupEpoch, 'string');
  });

  it('omits resetCursor on an up-to-date pull', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seq = (await (await pushEvent(app, groupId, secret)).json()).seq;
    const atTip = await (await pullEvents(app, groupId, secret, seq)).json();
    assert.deepEqual(atTip, { events: [], hasMore: false, recordCount: 1, groupEpoch: atTip.groupEpoch });
    const fromZero = await (await pullEvents(app, groupId, secret, 0)).json();
    assert.equal('resetCursor' in fromZero, false);
  });

  it('serves the same groupEpoch on every pull of one group incarnation', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const first = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(typeof first.groupEpoch, 'string');
    await pushEvent(app, groupId, secret);
    const second = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(second.groupEpoch, first.groupEpoch);
  });

  it('rejects an invalid since cursor', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const res = await pullEvents(app, groupId, secret, 'abc');
    assert.equal(res.status, 400);
  });

  it('round-trips the compressed flag and actorId', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    await pushEvent(app, groupId, secret, { actorId: 'alice-hash', compressed: true });
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(pulled.events[0].actorId, 'alice-hash');
    assert.equal(pulled.events[0].compressed, true);
  });
});

describe('compaction', () => {
  async function seed(app, count, secret, groupId) {
    const seqs = [];
    for (let i = 1; i <= count; i++) {
      const res = await pushEvent(app, groupId, secret, { eventData: `blob-${i}`, recordId: `r${i}` });
      seqs.push((await res.json()).seq);
    }
    return seqs;
  }

  it('replaces records up to the boundary with the uploaded ones at higher seqs', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 3, secret, groupId);

    const res = await compactGroup(app, groupId, secret, seqs[2], 3, [
      record('consolidated-1-2', { recordId: 'c1' }),
      record('consolidated-3', { recordId: 'c2' }),
    ]);
    assert.equal(res.status, 200);
    const { maxSeq } = await res.json();
    assert.ok(maxSeq > seqs[2]);

    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(pulled.recordCount, 2);
    assert.deepEqual(
      pulled.events.map((e) => e.eventData),
      ['consolidated-1-2', 'consolidated-3'],
    );
    assert.ok(pulled.events.every((e) => e.seq > seqs[2]));
  });

  it('leaves records beyond the boundary untouched', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 3, secret, groupId);

    const res = await compactGroup(app, groupId, secret, seqs[1], 2, [record('consolidated-1-2')]);
    assert.equal(res.status, 200);

    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.deepEqual(
      pulled.events.map((e) => e.eventData),
      ['blob-3', 'consolidated-1-2'],
    );
  });

  it('an old cursor keeps working after a compaction', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 3, secret, groupId);
    await compactGroup(app, groupId, secret, seqs[2], 3, [record('consolidated')]);

    const pulled = await (await pullEvents(app, groupId, secret, seqs[0])).json();
    assert.equal('resetCursor' in pulled, false);
    assert.deepEqual(pulled.events.map((e) => e.eventData), ['consolidated']);
  });

  it('rejects a boundary beyond the history with 409', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 1, secret, groupId);
    const res = await compactGroup(app, groupId, secret, seqs[0] + 10, 1, [record('consolidated')]);
    assert.equal(res.status, 409);
  });

  it('rejects a lost compaction race with 409', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 2, secret, groupId);
    assert.equal((await compactGroup(app, groupId, secret, seqs[1], 2, [record('winner')])).status, 200);
    // The loser's boundary now covers only deleted rows.
    const res = await compactGroup(app, groupId, secret, seqs[1], 2, [record('loser')]);
    assert.equal(res.status, 409);
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.deepEqual(pulled.events.map((e) => e.eventData), ['winner']);
  });

  it('rejects a compaction whose snapshot went stale even over a non-empty range', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 3, secret, groupId);
    assert.equal((await compactGroup(app, groupId, secret, seqs[2], 3, [record('winner')])).status, 200);
    const riderSeq = (await (await pushEvent(app, groupId, secret, { eventData: 'rider', recordId: 'rr' })).json())
      .seq;
    // A racer that pulled before the winner's compaction: its boundary
    // covers the fresh rider, so the delete range is non-empty, but the
    // record count betrays the stale snapshot.
    const res = await compactGroup(app, groupId, secret, riderSeq, 5, [record('stale-loser')]);
    assert.equal(res.status, 409);
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.deepEqual(pulled.events.map((e) => e.eventData), ['winner', 'rider']);
  });

  it('skips an uploaded record whose recordId survives above the boundary', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    const seqs = await seed(app, 2, secret, groupId);

    const res = await compactGroup(app, groupId, secret, seqs[0], 1, [
      record('duplicate-of-2', { recordId: 'r2' }),
      record('consolidated-1', { recordId: 'c1' }),
    ]);
    assert.equal(res.status, 200);
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.deepEqual(
      pulled.events.map((e) => e.eventData),
      ['blob-2', 'consolidated-1'],
    );
  });

  it('requires authentication', async () => {
    const app = makeApp().app;
    const { groupId } = await createGroup(app, { groupId: uid() });
    const res = await compactGroup(app, groupId, 'wrong-secret', 1, 1, [record('x')]);
    assert.equal(res.status, 401);
  });

  it('rejects a malformed body', async () => {
    const app = makeApp().app;
    const { groupId, secret } = await createGroup(app, { groupId: uid() });
    await seed(app, 1, secret, groupId);
    assert.equal((await compactGroup(app, groupId, secret, 0, 1, [record('x')])).status, 400);
    assert.equal((await compactGroup(app, groupId, secret, 1, 1, [])).status, 400);
    assert.equal((await compactGroup(app, groupId, secret, 1, 1, [{ eventData: 'x' }])).status, 400);
    assert.equal(
      (await compactGroup(app, groupId, secret, 1, 1, [record('x'.repeat(1024 * 1024 + 1))])).status,
      413,
    );
  });
});

describe('append notifications', () => {
  it('notifies onAppend with the new seq', async () => {
    const notified = [];
    const { app } = makeApp({ onAppend: (groupId, seq) => notified.push([groupId, seq]) });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret);
    assert.deepEqual(notified, [[groupId, 1]]);
  });
});

describe('health probe', () => {
  it('answers unauthenticated with an ok status', async () => {
    const { app } = makeApp();
    const res = await app.request('/health');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok' });
  });
});

describe('deployment config', () => {
  it('serves the configured push server url', async () => {
    const { app } = makeApp({ pushServerUrl: 'https://push.example.com' });
    const res = await app.request('/api/config');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { pushServerUrl: 'https://push.example.com' });
  });

  it('serves an empty push server url when the deployment ships without push', async () => {
    const { app } = makeApp();
    assert.deepEqual(await (await app.request('/api/config')).json(), { pushServerUrl: '' });
  });

  it('refuses a scheme-less push server url, which the frontend would read as relative', async () => {
    const { app } = makeApp({ pushServerUrl: 'push.example.com' });
    assert.deepEqual(await (await app.request('/api/config')).json(), { pushServerUrl: '' });
  });

  it('drops a trailing slash so appended paths stay well formed', async () => {
    const { app } = makeApp({ pushServerUrl: 'https://push.example.com/' });
    assert.deepEqual(await (await app.request('/api/config')).json(), {
      pushServerUrl: 'https://push.example.com',
    });
  });
});

describe('inactivity retention', () => {
  it('stamps last_access at group creation', async () => {
    const { app, storage } = makeApp();
    const { groupId } = await createGroup(app);
    assert.ok(storage.getLastAccess(groupId));
  });

  it('renews last_access at most once per interval', async () => {
    const { app, storage } = makeApp();
    const { groupId } = await createGroup(app);
    const now = '2030-01-02T00:00:00.000Z';
    const dayAgo = '2030-01-01T00:00:00.000Z';
    // The creation stamp is older than dayAgo → the first touch writes.
    assert.equal(storage.touchAccess(groupId, now, dayAgo), true);
    assert.equal(storage.getLastAccess(groupId), now);
    // last_access is no longer older than dayAgo → a follow-up is a no-op.
    assert.equal(storage.touchAccess(groupId, '2030-01-02T00:00:01.000Z', dayAgo), false);
    assert.equal(storage.getLastAccess(groupId), now);
  });

  it('renews last_access on an authenticated events request', async () => {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app);
    storage.touchAccess(groupId, '2000-01-01T00:00:00.000Z', '2999-01-01T00:00:00.000Z');
    await pullEvents(app, groupId, secret);
    assert.notEqual(storage.getLastAccess(groupId), '2000-01-01T00:00:00.000Z');
  });

  it('purges a group idle past the cutoff, along with its events', async () => {
    const { app, storage } = makeApp();
    const idle = await createGroup(app, { groupId: 'idle' });
    const active = await createGroup(app, { groupId: 'active' });
    await pushEvent(app, idle.groupId, idle.secret);

    storage.touchAccess(idle.groupId, '2000-01-01T00:00:00.000Z', '2999-01-01T00:00:00.000Z');
    assert.equal(storage.purgeIdleGroups('2001-01-01T00:00:00.000Z'), 1);

    // The purged group answers 404 — the client's next sync resurrects it.
    assert.equal((await pullEvents(app, idle.groupId, idle.secret)).status, 404);
    // A group accessed within the window is untouched.
    assert.equal((await pullEvents(app, active.groupId, active.secret)).status, 200);
  });

  it('a resurrected group serves a new epoch even when fresh appends mask the cursor gap', async () => {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app, { groupId: 'resur' });
    await pushEvent(app, groupId, secret, { recordId: 'old-1' });
    const staleCursor = (await (await pushEvent(app, groupId, secret, { recordId: 'old-2' })).json()).seq;
    const before = await (await pullEvents(app, groupId, secret)).json();

    storage.touchAccess(groupId, '2000-01-01T00:00:00.000Z', '2999-01-01T00:00:00.000Z');
    storage.purgeIdleGroups('2001-01-01T00:00:00.000Z');
    assert.equal((await createGroup(app, { groupId: 'resur', secret })).res.status, 201);

    // The events table's AUTOINCREMENT counter survives the purge, so a fresh
    // append lands above the stale cursor: this pull finds rows and cannot
    // signal resetCursor — the changed epoch is the only sign that the old
    // history is gone and the client must restart from 0 and re-push.
    await pushEvent(app, groupId, secret, { recordId: 'new-1' });
    const after = await (await pullEvents(app, groupId, secret, staleCursor)).json();
    assert.ok(after.events.length > 0);
    assert.equal('resetCursor' in after, false);
    assert.notEqual(after.groupEpoch, before.groupEpoch);
  });
});

describe('byte-bounded pull', () => {
  const TEN = '0123456789';

  it('caps a page by bytes and the cursor drains the remaining records in order', async () => {
    // Budget of 20 bytes fits two 10-byte records per page.
    const { app } = makeApp({ pullPageBytes: 20 });
    const { groupId, secret } = await createGroup(app);
    for (let i = 1; i <= 5; i++) {
      await pushEvent(app, groupId, secret, { eventData: TEN, recordId: `r${i}` });
    }

    const first = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(first.events.length, 2);
    assert.equal(first.hasMore, true);

    // Follow the cursor to completion and check nothing is dropped or reordered.
    const seqs = first.events.map((e) => e.seq);
    let page = first;
    while (page.hasMore) {
      page = await (await pullEvents(app, groupId, secret, page.events.at(-1).seq)).json();
      assert.ok(page.events.length >= 1);
      seqs.push(...page.events.map((e) => e.seq));
    }
    assert.deepEqual(seqs, [1, 2, 3, 4, 5]);
  });

  it('always returns at least one record even when it exceeds the byte budget', async () => {
    const { app } = makeApp({ pullPageBytes: 4 });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { eventData: TEN, recordId: 'r1' });
    await pushEvent(app, groupId, secret, { eventData: TEN, recordId: 'r2' });

    const page = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(page.events.length, 1);
    assert.equal(page.hasMore, true);
  });
});

describe('storage limits', () => {
  it('tracks record count and bytes, counting a batch once', async () => {
    const { app, storage } = makeApp({ appendLimits: GENEROUS });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { eventData: 'blob-a', recordId: 'r1' });
    // Re-pushing the same recordId is idempotent — it must not double-count.
    await pushEvent(app, groupId, secret, { eventData: 'blob-a', recordId: 'r1' });
    await pushEvent(app, groupId, secret, { eventData: 'blob-bb', recordId: 'r2' });

    const stats = storage.getGroupStats(groupId);
    assert.equal(stats.recordCount, 2);
    assert.equal(stats.totalBytes, 'blob-a'.length + 'blob-bb'.length);
  });

  it('rejects appends past the record cap with 507', async () => {
    const { app } = makeApp({ appendLimits: { ...GENEROUS, maxRecords: 2 } });
    const { groupId, secret } = await createGroup(app);
    assert.equal((await pushEvent(app, groupId, secret, { recordId: 'a' })).status, 201);
    assert.equal((await pushEvent(app, groupId, secret, { recordId: 'b' })).status, 201);
    assert.equal((await pushEvent(app, groupId, secret, { recordId: 'c' })).status, 507);
  });

  it('rejects appends past the byte cap with 507', async () => {
    const { app } = makeApp({ appendLimits: { ...GENEROUS, maxTotalBytes: 10 } });
    const { groupId, secret } = await createGroup(app);
    assert.equal((await pushEvent(app, groupId, secret, { eventData: 'short' })).status, 201);
    assert.equal((await pushEvent(app, groupId, secret, { eventData: 'too-long-now' })).status, 507);
  });

  it('rejects appends past the monthly rate cap with 429 and a Retry-After hint', async () => {
    const { app } = makeApp({ appendLimits: { ...GENEROUS, rateBytes: 10, windowMs: 60 * 60 * 1000 } });
    const { groupId, secret } = await createGroup(app);
    assert.equal((await pushEvent(app, groupId, secret, { eventData: 'short' })).status, 201);
    const res = await pushEvent(app, groupId, secret, { eventData: 'more-bytes' });
    assert.equal(res.status, 429);
    assert.ok(Number(res.headers.get('Retry-After')) > 0);
  });

  it('a shrinking compaction updates the exact counters and spends no rate budget', async () => {
    const { app, storage } = makeApp({ appendLimits: GENEROUS });
    const { groupId, secret } = await createGroup(app);
    let lastSeq = 0;
    for (let i = 1; i <= 3; i++) {
      lastSeq = (await (await pushEvent(app, groupId, secret, { eventData: '0123456789', recordId: `r${i}` })).json())
        .seq;
    }
    assert.equal(storage.getGroupStats(groupId).bytesThisWindow, 30);

    const res = await compactGroup(app, groupId, secret, lastSeq, 3, [record('consolidated', { recordId: 'c1' })]);
    assert.equal(res.status, 200);
    const stats = storage.getGroupStats(groupId);
    assert.equal(stats.recordCount, 1);
    assert.equal(stats.totalBytes, 'consolidated'.length);
    assert.equal(stats.bytesThisWindow, 30);
  });

  it('a growing compaction pays its net bytes against the rate cap', async () => {
    const { app } = makeApp({ appendLimits: { ...GENEROUS, rateBytes: 25, windowMs: 60 * 60 * 1000 } });
    const { groupId, secret } = await createGroup(app);
    const seq = (await (await pushEvent(app, groupId, secret, { eventData: '0123456789' })).json()).seq;
    // Net growth of 20 bytes on top of the 10 already spent exceeds 25.
    const res = await compactGroup(app, groupId, secret, seq, 1, [record('0123456789012345678901234567890')]);
    assert.equal(res.status, 429);
    // The rejected compaction changed nothing.
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.deepEqual(pulled.events.map((e) => e.eventData), ['0123456789']);
  });

  it('a compaction that would overflow the byte quota is rejected with 507', async () => {
    const { app } = makeApp({ appendLimits: { ...GENEROUS, maxTotalBytes: 15 } });
    const { groupId, secret } = await createGroup(app);
    const seq = (await (await pushEvent(app, groupId, secret, { eventData: '0123456789' })).json()).seq;
    const res = await compactGroup(app, groupId, secret, seq, 1, [record('0123456789012345678901234567890')]);
    assert.equal(res.status, 507);
  });
});
