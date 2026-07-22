/**
 * Protocol conformance suite, shared by both adapters: the Node app runs it
 * under node:test (test/app.test.js) and the Cloudflare Worker under
 * vitest-pool-workers (test-workers/relay.spec.js). Callers inject their
 * runner's describe/it and an async makeApp() returning a fresh
 * `{request(path, init)}` client.
 */

import assert from 'node:assert/strict';
import { createGroup, pushEvent, pullEvents, compactGroup, record, solvedPow, sha256Base64Url } from './protocol-helpers.js';

export function conformanceSuite({ describe, it, makeApp }) {
  // The worker runner shares one live instance across the whole suite (no
  // per-test storage isolation), so every test works on its own group ids.
  let nextGroup = 0;
  const uid = () => `g${nextGroup++}`;

  describe('group creation', () => {
    it('creates a group with a valid PoW solution', async () => {
      const app = await makeApp();
      const { res } = await createGroup(app, { groupId: uid() });
      assert.equal(res.status, 201);
    });

    it('rejects creation without PoW', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
      const res = await app.request('/api/pow/challenge');
      assert.equal(res.status, 400);
    });

    it('rejects a challenge reused for another group', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
      const groupId = uid();
      await createGroup(app, { groupId });
      const { res } = await createGroup(app, { groupId });
      assert.equal(res.status, 409);
      assert.match((await res.json()).error, /already exists/);
    });
  });

  describe('events auth', () => {
    it('rejects requests without a bearer token', async () => {
      const app = await makeApp();
      const { groupId } = await createGroup(app, { groupId: uid() });
      const res = await app.request(`/api/groups/${groupId}/events`);
      assert.equal(res.status, 401);
    });

    it('rejects a wrong secret', async () => {
      const app = await makeApp();
      const { groupId } = await createGroup(app, { groupId: uid() });
      const res = await pullEvents(app, groupId, 'wrong-secret');
      assert.equal(res.status, 401);
    });

    it('returns 404 for an unknown group', async () => {
      const app = await makeApp();
      const res = await pullEvents(app, 'nope', 'any-secret');
      assert.equal(res.status, 404);
    });

    it("rejects one group's secret on another group", async () => {
      const app = await makeApp();
      const a = await createGroup(app, { groupId: uid() });
      const b = await createGroup(app, { groupId: uid() });
      const res = await pullEvents(app, b.groupId, a.secret);
      assert.equal(res.status, 401);
    });
  });

  describe('event push and pull', () => {
    it('appends events with increasing seq and pulls from a cursor', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
      const a = await createGroup(app, { groupId: uid() });
      const b = await createGroup(app, { groupId: uid() });
      await pushEvent(app, a.groupId, a.secret, { eventData: 'from-a' });
      const pulled = await (await pullEvents(app, b.groupId, b.secret)).json();
      assert.deepEqual(pulled.events, []);
    });

    it('paginates pulls at 200 events', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const res = await pushEvent(app, groupId, secret, {
        eventData: 'x'.repeat(1024 * 1024 + 1),
      });
      assert.equal(res.status, 413);
    });

    it('replaying a recordId returns the original seq without inserting', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
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
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const empty = await pushEvent(app, groupId, secret, { recordId: '' });
      assert.equal(empty.status, 400);
      const long = await pushEvent(app, groupId, secret, { recordId: 'x'.repeat(201) });
      assert.equal(long.status, 400);
    });

    it('asks for a cursor reset when since is beyond the group history', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const seq = (await (await pushEvent(app, groupId, secret)).json()).seq;
      const pulled = await (await pullEvents(app, groupId, secret, seq + 10)).json();
      assert.deepEqual(pulled, { events: [], hasMore: false, recordCount: 1, groupEpoch: pulled.groupEpoch, resetCursor: true });
      assert.equal(typeof pulled.groupEpoch, 'string');
    });

    it('asks for a cursor reset when the group has no events but since > 0', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const pulled = await (await pullEvents(app, groupId, secret, 5)).json();
      assert.deepEqual(pulled, { events: [], hasMore: false, recordCount: 0, groupEpoch: pulled.groupEpoch, resetCursor: true });
      assert.equal(typeof pulled.groupEpoch, 'string');
    });

    it('omits resetCursor on an up-to-date pull', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const seq = (await (await pushEvent(app, groupId, secret)).json()).seq;
      const atTip = await (await pullEvents(app, groupId, secret, seq)).json();
      assert.deepEqual(atTip, { events: [], hasMore: false, recordCount: 1, groupEpoch: atTip.groupEpoch });
      const fromZero = await (await pullEvents(app, groupId, secret, 0)).json();
      assert.equal('resetCursor' in fromZero, false);
    });

    it('serves the same groupEpoch on every pull of one group incarnation', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const first = await (await pullEvents(app, groupId, secret)).json();
      assert.equal(typeof first.groupEpoch, 'string');
      await pushEvent(app, groupId, secret);
      const second = await (await pullEvents(app, groupId, secret)).json();
      assert.equal(second.groupEpoch, first.groupEpoch);
    });

    it('rejects an invalid since cursor', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const res = await pullEvents(app, groupId, secret, 'abc');
      assert.equal(res.status, 400);
    });

    it('round-trips the compressed flag and actorId', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
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
      const app = await makeApp();
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
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const seqs = await seed(app, 3, secret, groupId);
      await compactGroup(app, groupId, secret, seqs[2], 3, [record('consolidated')]);

      const pulled = await (await pullEvents(app, groupId, secret, seqs[0])).json();
      assert.equal('resetCursor' in pulled, false);
      assert.deepEqual(pulled.events.map((e) => e.eventData), ['consolidated']);
    });

    it('rejects a boundary beyond the history with 409', async () => {
      const app = await makeApp();
      const { groupId, secret } = await createGroup(app, { groupId: uid() });
      const seqs = await seed(app, 1, secret, groupId);
      const res = await compactGroup(app, groupId, secret, seqs[0] + 10, 1, [record('consolidated')]);
      assert.equal(res.status, 409);
    });

    it('rejects a lost compaction race with 409', async () => {
      const app = await makeApp();
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
      const app = await makeApp();
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
      const app = await makeApp();
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
      const app = await makeApp();
      const { groupId } = await createGroup(app, { groupId: uid() });
      const res = await compactGroup(app, groupId, 'wrong-secret', 1, 1, [record('x')]);
      assert.equal(res.status, 401);
    });

    it('rejects a malformed body', async () => {
      const app = await makeApp();
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
}
