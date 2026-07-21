import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { openStorage } from '../src/storage-sqlite.js';
import { makeApp, createGroup, pushEvent, pullEvents, compactGroup, record } from './helpers.js';

const GENEROUS = { maxRecords: 50000, maxTotalBytes: 50 * 1024 * 1024, rateBytes: 10 * 1024 * 1024, windowMs: 1000 };

function dailyTotals(storage) {
  const totals = {};
  for (const row of storage.getDailySince('')) {
    totals[row.name] = (totals[row.name] ?? 0) + row.value;
  }
  return totals;
}

describe('daily table', () => {
  it('bumpMetric accumulates within a (day, name) and getDailySince filters by day', () => {
    const storage = openStorage(':memory:');
    storage.bumpMetric('quota_507', '2030-01-01');
    storage.bumpMetric('quota_507', '2030-01-01', 4);
    storage.bumpMetric('quota_507', '2030-01-02');
    assert.deepEqual(storage.getDailySince('2030-01-01'), [
      { day: '2030-01-01', name: 'quota_507', value: 5 },
      { day: '2030-01-02', name: 'quota_507', value: 1 },
    ]);
    assert.deepEqual(storage.getDailySince('2030-01-02'), [{ day: '2030-01-02', name: 'quota_507', value: 1 }]);
    storage.close();
  });

  it('recordDailyLevels replaces the day, never adds to it', () => {
    const storage = openStorage(':memory:');
    storage.recordDailyLevels('2030-01-01', { total_groups: 3, total_bytes: 100 });
    storage.recordDailyLevels('2030-01-01', { total_groups: 5, total_bytes: 250 });
    assert.deepEqual(dailyTotals(storage), { total_groups: 5, total_bytes: 250 });
    storage.close();
  });

  it('getFleetLevels rolls up groups, bytes, actors and percentiles', () => {
    const storage = openStorage(':memory:');
    const mk = (id, created) =>
      storage.createGroup({ groupId: id, createdBy: 'c', authVerifier: 'v', powChallenge: 'p', created });
    mk('a', '2030-01-01T00:00:00.000Z');
    mk('b', '2030-06-01T00:00:00.000Z');
    // a stays idle at its creation stamp; b is touched into the active window.
    storage.touchAccess('b', '2030-06-01T00:00:00.000Z', '2999-01-01T00:00:00.000Z');
    const push = (id, actor, data, created) =>
      storage.appendEvent(id, { recordId: null, actorId: actor, eventData: data, compressed: false, created }, GENEROUS);
    push('a', 'alice', 'aaaaa', '2030-01-01T00:00:00.000Z'); // 5 bytes
    push('a', 'alice', 'bbb', '2030-01-02T00:00:00.000Z'); // 3 bytes → group a: 8 bytes, 2 records
    push('b', 'bob', 'cccccccccc', '2030-06-01T00:00:00.000Z'); // 10 bytes → group b: 10 bytes, 1 record

    const levels = storage.getFleetLevels({
      idleCutoff: '2030-03-01T00:00:00.000Z',
      nearQuotaBytes: 9,
      nearQuotaRecords: 100,
      actorWindows: [{ name: 'active_actors_7d', since: '2030-05-25T00:00:00.000Z' }],
    });
    assert.equal(levels.total_groups, 2);
    assert.equal(levels.active_groups, 1);
    assert.equal(levels.idle_groups, 1);
    assert.equal(levels.total_bytes, 18);
    assert.equal(levels.total_records, 3);
    assert.equal(levels.max_bytes, 10);
    assert.equal(levels.p50_bytes, 8);
    assert.equal(levels.groups_near_quota, 1);
    assert.equal(levels.distinct_actors_cumulative, 2);
    assert.equal(levels.active_actors_7d, 1);
    storage.close();
  });

  it('reports zeroed levels for an empty fleet', () => {
    const storage = openStorage(':memory:');
    const levels = storage.getFleetLevels({
      idleCutoff: '2030-01-01T00:00:00.000Z',
      nearQuotaBytes: 1,
      nearQuotaRecords: 1,
      actorWindows: [{ name: 'active_actors_1d', since: '2030-01-01T00:00:00.000Z' }],
    });
    assert.equal(levels.total_groups, 0);
    assert.equal(levels.total_bytes, 0);
    assert.equal(levels.p50_bytes, 0);
    assert.equal(levels.p95_bytes, 0);
    assert.equal(levels.distinct_actors_cumulative, 0);
    assert.equal(levels.active_actors_1d, 0);
    storage.close();
  });
});

describe('request counters', () => {
  it('counts a missing and a wrong bearer as auth failures', async () => {
    const { app, storage } = makeApp();
    const { groupId } = await createGroup(app);
    await app.request(`/api/groups/${groupId}/events`);
    await pullEvents(app, groupId, 'wrong-secret');
    assert.equal(dailyTotals(storage).auth_401, 2);
  });

  it('counts group creations and issued PoW challenges', async () => {
    const { app, storage } = makeApp();
    await createGroup(app);
    const totals = dailyTotals(storage);
    assert.equal(totals.group_created, 1);
    assert.ok(totals.pow_issued >= 1);
  });

  it('counts a storage-quota rejection', async () => {
    const { app, storage } = makeApp({ appendLimits: { ...GENEROUS, maxRecords: 1 } });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { recordId: 'a' });
    await pushEvent(app, groupId, secret, { recordId: 'b' });
    assert.equal(dailyTotals(storage).quota_507, 1);
  });

  it('counts a rate-cap rejection', async () => {
    const { app, storage } = makeApp({ appendLimits: { ...GENEROUS, rateBytes: 5, windowMs: 60 * 60 * 1000 } });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { eventData: 'short' });
    await pushEvent(app, groupId, secret, { eventData: 'more-bytes' });
    assert.equal(dailyTotals(storage).rate_429, 1);
  });

  it('counts an oversized-event rejection', async () => {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { eventData: 'x'.repeat(1024 * 1024 + 1) });
    assert.equal(dailyTotals(storage).body_413, 1);
  });

  it('counts bytes served on a pull', async () => {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { eventData: 'hello' });
    await pullEvents(app, groupId, secret);
    assert.equal(dailyTotals(storage).bytes_served, 'hello'.length);
  });

  it('counts a compaction and the bytes it reclaims', async () => {
    const { app, storage } = makeApp({ appendLimits: GENEROUS });
    const { groupId, secret } = await createGroup(app);
    let lastSeq = 0;
    for (let i = 1; i <= 3; i++) {
      lastSeq = (await (await pushEvent(app, groupId, secret, { eventData: '0123456789', recordId: `r${i}` })).json())
        .seq;
    }
    await compactGroup(app, groupId, secret, lastSeq, 3, [record('consolidated', { recordId: 'c1' })]);
    const totals = dailyTotals(storage);
    assert.equal(totals.compaction_ops, 1);
    assert.equal(totals.compaction_bytes_reclaimed, 30 - 'consolidated'.length);
  });
});
