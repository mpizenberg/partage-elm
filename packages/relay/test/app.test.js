import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { conformanceSuite } from './conformance.js';
import { makeApp, createGroup, pushEvent, pullEvents } from './helpers.js';

const GENEROUS = { maxRecords: 50000, maxTotalBytes: 50 * 1024 * 1024, rateBytes: 10 * 1024 * 1024, windowMs: 1000 };

conformanceSuite({ describe, it, makeApp: async () => makeApp().app });

describe('node adapter specifics', () => {
  it('notifies onAppend with the new seq', async () => {
    const notified = [];
    const { app } = makeApp({ onAppend: (groupId, seq) => notified.push([groupId, seq]) });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret);
    assert.deepEqual(notified, [[groupId, 1]]);
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
});
