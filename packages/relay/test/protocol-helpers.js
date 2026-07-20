/**
 * Runner-agnostic protocol helpers: everything here talks to an `app` object
 * exposing `request(path, init) → Promise<Response>` and uses only node:crypto
 * (available in workerd via nodejs_compat), so the same helpers drive both the
 * in-process Node app and the Cloudflare Worker under vitest-pool-workers.
 */

import { createHash, createHmac } from 'node:crypto';

export const TEST_SECRET = 'test-pow-secret';

/** Brute-force a PoW nonce with sync hashing (fast enough for difficulty 18). */
export function solve(challenge, difficulty) {
  for (let nonce = 0; ; nonce++) {
    const hash = createHash('sha256').update(challenge + nonce).digest();
    let zeroBits = 0;
    for (const byte of hash) {
      if (byte === 0) {
        zeroBits += 8;
        if (zeroBits >= difficulty) break;
      } else {
        zeroBits += Math.clz32(byte) - 24;
        break;
      }
    }
    if (zeroBits >= difficulty) {
      return String(nonce);
    }
  }
}

export function signChallenge(challenge, groupId, timestamp, difficulty, secret = TEST_SECRET) {
  return createHmac('sha256', secret)
    .update(`${challenge}:${groupId}:${timestamp}:${difficulty}`)
    .digest('hex');
}

/** Fetch a challenge from the app, solve it, and return the pow_* body fields. */
export async function solvedPow(app, groupId) {
  const res = await app.request(`/api/pow/challenge?groupId=${groupId}`);
  const challenge = await res.json();
  return {
    pow_challenge: challenge.challenge,
    pow_timestamp: challenge.timestamp,
    pow_difficulty: challenge.difficulty,
    pow_signature: challenge.signature,
    pow_solution: solve(challenge.challenge, challenge.difficulty),
  };
}

export function sha256Base64Url(text) {
  return createHash('sha256').update(text).digest('base64url');
}

export async function createGroup(app, { groupId = 'g1', secret = 'group-secret-' + groupId } = {}) {
  const res = await app.request('/api/groups', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      groupId,
      createdBy: 'creator-key-hash',
      authVerifier: sha256Base64Url(secret),
      ...(await solvedPow(app, groupId)),
    }),
  });
  return { res, groupId, secret };
}

export function pushEvent(app, groupId, secret, body = {}) {
  return app.request(`/api/groups/${groupId}/events`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${secret}`,
    },
    body: JSON.stringify({
      actorId: 'actor-key-hash',
      eventData: '{"ciphertext":"AAAA","iv":"BBBB"}',
      compressed: false,
      ...body,
    }),
  });
}

export function pullEvents(app, groupId, secret, since = 0) {
  return app.request(`/api/groups/${groupId}/events?since=${since}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
}

export function compactGroup(app, groupId, secret, uptoSeq, records) {
  return app.request(`/api/groups/${groupId}/compact`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${secret}`,
    },
    body: JSON.stringify({ uptoSeq, records }),
  });
}

/** A consolidation record for compact bodies, with sensible defaults. */
export function record(eventData, overrides = {}) {
  return { actorId: 'actor-key-hash', eventData, compressed: false, ...overrides };
}
