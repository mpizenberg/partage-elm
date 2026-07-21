import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp } from './helpers.js';

const ADMIN = 'operator-secret';
const GENEROUS = { maxRecords: 50000, maxTotalBytes: 50 * 1024 * 1024, rateBytes: 10 * 1024 * 1024, windowMs: 1000 };
const today = new Date().toISOString().slice(0, 10);
const dayAgo = (n) => new Date(Date.now() - n * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

function mkGroup(storage, id, created) {
  storage.createGroup({ groupId: id, createdBy: 'c', authVerifier: 'v', powChallenge: 'p', created });
}
function push(storage, id, actor, data) {
  storage.appendEvent(
    id,
    { recordId: null, actorId: actor, eventData: data, compressed: false, created: new Date().toISOString() },
    GENEROUS,
  );
}
function summary(app, { secret = ADMIN, query = '' } = {}) {
  const headers = secret === null ? {} : { Authorization: `Bearer ${secret}` };
  return app.request(`/api/admin/summary${query}`, { headers });
}

describe('admin endpoint auth', () => {
  it('is absent (404) unless ADMIN_SECRET is configured', async () => {
    const { app } = makeApp();
    assert.equal((await summary(app)).status, 404);
  });

  it('rejects a missing or wrong bearer and accepts the right one', async () => {
    const { app } = makeApp({ adminSecret: ADMIN });
    assert.equal((await summary(app, { secret: null })).status, 401);
    assert.equal((await summary(app, { secret: 'nope' })).status, 401);
    assert.equal((await summary(app)).status, 200);
  });
});

describe('admin auth rate limiting', () => {
  const attempt = (app, { secret, ip }) =>
    app.request('/api/admin/summary', {
      headers: { Authorization: `Bearer ${secret}`, 'X-Forwarded-For': ip },
    });

  it('locks out an address after repeated failures, but not a correct secret elsewhere', async () => {
    const { app } = makeApp({ adminSecret: ADMIN });

    let firstBlock = -1;
    for (let i = 0; i < 20; i++) {
      const status = (await attempt(app, { secret: 'wrong', ip: '1.1.1.1' })).status;
      if (status === 429) {
        firstBlock = i;
        break;
      }
      assert.equal(status, 401);
    }
    assert.ok(firstBlock >= 1, 'a lockout follows some plain 401s');

    const blocked = await attempt(app, { secret: 'wrong', ip: '1.1.1.1' });
    assert.equal(blocked.status, 429);
    assert.ok(blocked.headers.get('retry-after'));

    // The correct secret is short-circuited from the locked address...
    assert.equal((await attempt(app, { secret: ADMIN, ip: '1.1.1.1' })).status, 429);
    // ...but works from a fresh one, and a fresh address is not pre-locked.
    assert.equal((await attempt(app, { secret: ADMIN, ip: '2.2.2.2' })).status, 200);
    assert.equal((await attempt(app, { secret: 'wrong', ip: '3.3.3.3' })).status, 401);
  });

  it('does not count a successful auth toward the lockout', async () => {
    const { app } = makeApp({ adminSecret: ADMIN });
    for (let i = 0; i < 20; i++) {
      assert.equal((await attempt(app, { secret: ADMIN, ip: '4.4.4.4' })).status, 200);
    }
  });
});

describe('admin summary content', () => {
  it('reports current fleet levels in the now section', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    mkGroup(storage, 'a', '2030-01-01T00:00:00.000Z');
    mkGroup(storage, 'b', '2030-01-02T00:00:00.000Z');
    push(storage, 'a', 'alice', 'aaaa');
    push(storage, 'b', 'bob', 'bbbbbb');
    const body = await (await summary(app)).json();
    assert.equal(body.now.total_groups, 2);
    assert.equal(body.now.total_bytes, 10);
    assert.equal(body.now.distinct_actors_cumulative, 2);
  });

  it('ranks hot-lists by bytes, records and actor count', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    mkGroup(storage, 'small', '2030-01-03T00:00:00.000Z');
    mkGroup(storage, 'big', '2030-01-01T00:00:00.000Z');
    mkGroup(storage, 'mid', '2030-01-02T00:00:00.000Z');
    push(storage, 'small', 'x', 'a');
    push(storage, 'mid', 'x', 'aaaaa');
    push(storage, 'big', 'x', 'aaaaaaaaaa');
    push(storage, 'big', 'y', 'a'); // big: 2 records, 2 actors
    const { hotlists } = await (await summary(app)).json();
    assert.deepEqual(
      hotlists.largestByBytes.map((r) => r.groupId),
      ['big', 'mid', 'small'],
    );
    assert.equal(hotlists.largestByBytes[0].totalBytes, 11);
    assert.equal(hotlists.largestByRecords[0].groupId, 'big');
    assert.equal(hotlists.largestByRecords[0].recordCount, 2);
    assert.equal(hotlists.oldestActive[0].groupId, 'big'); // earliest created among active
    assert.equal(hotlists.mostActors[0].groupId, 'big');
    assert.equal(hotlists.mostActors[0].actors, 2);
  });

  it('windows the history by ?days=', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    storage.bumpMetric('quota_507', today, 1);
    storage.bumpMetric('quota_507', dayAgo(1), 1);
    storage.bumpMetric('quota_507', dayAgo(10), 1);
    const days = (body) => new Set(body.history.map((r) => r.day));
    const two = days(await (await summary(app, { query: '?days=2' })).json());
    assert.ok(two.has(today) && two.has(dayAgo(1)) && !two.has(dayAgo(10)));
    const all = days(await (await summary(app, { query: '?days=365' })).json());
    assert.ok(all.has(dayAgo(10)));
  });
});

describe('admin flags', () => {
  it('flags a group near capacity', async () => {
    const { app, storage } = makeApp({
      adminSecret: ADMIN,
      appendLimits: { ...GENEROUS, maxTotalBytes: 100 },
    });
    mkGroup(storage, 'full', '2030-01-01T00:00:00.000Z');
    push(storage, 'full', 'x', 'z'.repeat(80));
    const { flags } = await (await summary(app)).json();
    assert.equal(flags.nearCapacity.active, true);
    assert.equal(flags.nearCapacity.groupsNearQuota, 1);
  });

  it('flags auth probing above the daily threshold', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    storage.bumpMetric('auth_401', today, 51);
    const { flags } = await (await summary(app)).json();
    assert.equal(flags.authProbing.active, true);
    assert.equal(flags.authProbing.count, 51);
  });

  it('flags a rejection spike over the floor when history is flat', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    storage.bumpMetric('quota_507', today, 40);
    storage.bumpMetric('rate_429', today, 20); // 60 rejections today, threshold max(50, 3*0)
    const { flags } = await (await summary(app)).json();
    assert.equal(flags.rejectionSpike.threshold, 50);
    assert.equal(flags.rejectionSpike.count, 60);
    assert.equal(flags.rejectionSpike.active, true);
  });

  it('flags storage over budget only when a budget is set', async () => {
    const withBudget = makeApp({ adminSecret: ADMIN, adminStorageBudgetBytes: 5 });
    mkGroup(withBudget.storage, 'g', '2030-01-01T00:00:00.000Z');
    push(withBudget.storage, 'g', 'x', 'aaaaaaaa'); // 8 > 5
    const flagged = (await (await summary(withBudget.app)).json()).flags.storageOverBudget;
    assert.equal(flagged.active, true);
    assert.equal(flagged.budgetBytes, 5);

    const noBudget = makeApp({ adminSecret: ADMIN });
    mkGroup(noBudget.storage, 'g', '2030-01-01T00:00:00.000Z');
    push(noBudget.storage, 'g', 'x', 'aaaaaaaa');
    const unset = (await (await summary(noBudget.app)).json()).flags.storageOverBudget;
    assert.equal(unset.active, false);
    assert.equal(unset.budgetBytes, null);
  });
});

describe('admin cost', () => {
  it('computes a monthly run-rate from total bytes and trailing egress', async () => {
    const { app, storage } = makeApp({ adminSecret: ADMIN });
    mkGroup(storage, 'g', '2030-01-01T00:00:00.000Z');
    push(storage, 'g', 'x', 'a'.repeat(100)); // 100 total bytes
    storage.bumpMetric('bytes_served', today, 200);
    const { cost } = await (await summary(app)).json();
    assert.equal(cost.baseCents, 10);
    assert.equal(cost.storageCents, (100 / 1e9) * 10);
    assert.equal(cost.computeCents, (100 / 1e9) * 10 * 5);
    assert.equal(cost.networkCents, (200 / 1e9) * 10);
    assert.equal(cost.totalBytes, 100);
    assert.equal(cost.monthlyBytesServed, 200);
    assert.equal(cost.totalCents, cost.baseCents + cost.storageCents + cost.computeCents + cost.networkCents);
  });
});
