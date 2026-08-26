import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { makeApp, TEST_SECRET, createGroup, pushEvent, pullEvents, compactGroup, record } from '../test-support/helpers.js';

describe('migration configuration', () => {
  it('serves the migration endpoints over /api/config, trailing slashes stripped', async () => {
    const { app } = makeApp({
      migrationTarget: 'https://new.example.com/',
      migrationSource: 'https://old.example.com',
    });
    const config = await (await app.request('/api/config')).json();
    assert.equal(config.migrationTarget, 'https://new.example.com');
    assert.equal(config.migrationSource, 'https://old.example.com');
  });

  it('serves empty strings when unset', async () => {
    const config = await (await makeApp().app.request('/api/config')).json();
    assert.equal(config.migrationTarget, '');
    assert.equal(config.migrationSource, '');
  });

  it('ignores a migration URL without a scheme', async () => {
    const { app } = makeApp({ migrationTarget: 'new.example.com' });
    const config = await (await app.request('/api/config')).json();
    assert.equal(config.migrationTarget, '');
  });

  it('lets pages address the migration target origin', async () => {
    const res = await makeApp({ migrationTarget: 'https://new.example.com/some/path' }).app.request('/health');
    assert.match(res.headers.get('content-security-policy'), /connect-src [^;]*https:\/\/new\.example\.com/);
  });
});

describe('read-only relay', () => {
  async function frozenAppWithGroup() {
    const { app, storage } = makeApp();
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret, { recordId: 'r1' });
    const frozen = createApp({ storage, powSecret: TEST_SECRET, readOnly: true });
    return { frozen, writable: app, groupId, secret };
  }

  it('refuses group creation with the distinctive code', async () => {
    const { frozen } = await frozenAppWithGroup();
    const { res } = await createGroup(frozen, { groupId: 'g-new' });
    assert.equal(res.status, 403);
    assert.equal((await res.json()).code, 'relay_read_only');
  });

  it('refuses appends with the distinctive code', async () => {
    const { frozen, groupId, secret } = await frozenAppWithGroup();
    const res = await pushEvent(frozen, groupId, secret, { recordId: 'r2' });
    assert.equal(res.status, 403);
    assert.equal((await res.json()).code, 'relay_read_only');
  });

  it('refuses compaction with the distinctive code', async () => {
    const { frozen, groupId, secret } = await frozenAppWithGroup();
    const res = await compactGroup(frozen, groupId, secret, 1, 1, [record('{"ciphertext":"CC","iv":"DD"}')]);
    assert.equal(res.status, 403);
  });

  it('keeps serving pulls', async () => {
    const { frozen, groupId, secret } = await frozenAppWithGroup();
    const res = await pullEvents(frozen, groupId, secret);
    assert.equal(res.status, 200);
    assert.equal((await res.json()).events.length, 1);
  });

  it('keeps serving /api/config and /health', async () => {
    const { frozen } = await frozenAppWithGroup();
    assert.equal((await frozen.request('/api/config')).status, 200);
    assert.equal((await frozen.request('/health')).status, 200);
  });
});
