import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeApp,
  createGroup,
  pushEvent,
  pullEvents,
  solvedPow,
  sha256Base64Url,
} from './helpers.js';

describe('group creation', () => {
  it('creates a group with a valid PoW solution', async () => {
    const { app } = makeApp();
    const { res } = await createGroup(app);
    assert.equal(res.status, 201);
  });

  it('rejects creation without PoW', async () => {
    const { app } = makeApp();
    const res = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        groupId: 'g1',
        createdBy: 'creator',
        authVerifier: sha256Base64Url('secret'),
      }),
    });
    assert.equal(res.status, 400);
  });

  it('rejects a reused challenge', async () => {
    const { app } = makeApp();
    const pow = await solvedPow(app);
    const body = (groupId) => ({
      groupId,
      createdBy: 'creator',
      authVerifier: sha256Base64Url('secret'),
      ...pow,
    });
    const first = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body('g1')),
    });
    assert.equal(first.status, 201);
    const second = await app.request('/api/groups', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body('g2')),
    });
    assert.equal(second.status, 409);
    assert.match((await second.json()).error, /already used/);
  });

  it('rejects a duplicate groupId', async () => {
    const { app } = makeApp();
    await createGroup(app, { groupId: 'g1' });
    const { res } = await createGroup(app, { groupId: 'g1' });
    assert.equal(res.status, 409);
    assert.match((await res.json()).error, /already exists/);
  });
});

describe('events auth', () => {
  it('rejects requests without a bearer token', async () => {
    const { app } = makeApp();
    const { groupId } = await createGroup(app);
    const res = await app.request(`/api/groups/${groupId}/events`);
    assert.equal(res.status, 401);
  });

  it('rejects a wrong secret', async () => {
    const { app } = makeApp();
    const { groupId } = await createGroup(app);
    const res = await pullEvents(app, groupId, 'wrong-secret');
    assert.equal(res.status, 401);
  });

  it('returns 404 for an unknown group', async () => {
    const { app } = makeApp();
    const res = await pullEvents(app, 'nope', 'any-secret');
    assert.equal(res.status, 404);
  });

  it("rejects one group's secret on another group", async () => {
    const { app } = makeApp();
    const a = await createGroup(app, { groupId: 'ga' });
    const b = await createGroup(app, { groupId: 'gb' });
    const res = await pullEvents(app, b.groupId, a.secret);
    assert.equal(res.status, 401);
  });
});

describe('event push and pull', () => {
  it('appends events with increasing seq and pulls from a cursor', async () => {
    const { app } = makeApp();
    const { groupId, secret } = await createGroup(app);

    for (let i = 1; i <= 3; i++) {
      const res = await pushEvent(app, groupId, secret, { eventData: `blob-${i}` });
      assert.equal(res.status, 201);
      assert.equal((await res.json()).seq, i);
    }

    const all = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(all.hasMore, false);
    assert.deepEqual(
      all.events.map((e) => [e.seq, e.eventData]),
      [[1, 'blob-1'], [2, 'blob-2'], [3, 'blob-3']],
    );

    const tail = await (await pullEvents(app, groupId, secret, 2)).json();
    assert.deepEqual(tail.events.map((e) => e.seq), [3]);
  });

  it('scopes events to their group', async () => {
    const { app } = makeApp();
    const a = await createGroup(app, { groupId: 'ga' });
    const b = await createGroup(app, { groupId: 'gb' });
    await pushEvent(app, a.groupId, a.secret, { eventData: 'from-a' });
    const pulled = await (await pullEvents(app, b.groupId, b.secret)).json();
    assert.deepEqual(pulled.events, []);
  });

  it('paginates pulls at 200 events', async () => {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app);
    for (let i = 0; i < 201; i++) {
      storage.appendEvent(groupId, {
        actorId: 'actor',
        eventData: `blob-${i}`,
        compressed: false,
        created: '2026-01-01T00:00:00.000Z',
      });
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
    const { app } = makeApp();
    const { groupId, secret } = await createGroup(app);
    const res = await pushEvent(app, groupId, secret, {
      eventData: 'x'.repeat(1024 * 1024 + 1),
    });
    assert.equal(res.status, 413);
  });

  it('rejects an invalid since cursor', async () => {
    const { app } = makeApp();
    const { groupId, secret } = await createGroup(app);
    const res = await pullEvents(app, groupId, secret, 'abc');
    assert.equal(res.status, 400);
  });

  it('notifies onAppend with the new seq', async () => {
    const notified = [];
    const { app } = makeApp({ onAppend: (groupId, seq) => notified.push([groupId, seq]) });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret);
    assert.deepEqual(notified, [[groupId, 1]]);
  });

  it('round-trips the compressed flag and actorId', async () => {
    const { app } = makeApp();
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { actorId: 'alice-hash', compressed: true });
    const pulled = await (await pullEvents(app, groupId, secret)).json();
    assert.equal(pulled.events[0].actorId, 'alice-hash');
    assert.equal(pulled.events[0].compressed, true);
  });
});
