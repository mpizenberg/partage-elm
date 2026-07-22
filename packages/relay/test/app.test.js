import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { conformanceSuite } from './conformance.js';
import { makeApp, createGroup, pushEvent, pullEvents, compactGroup, record } from './helpers.js';

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
