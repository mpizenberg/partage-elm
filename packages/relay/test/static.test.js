import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/node-server.js';
import { openStorage } from '../src/storage.js';
import { TEST_SECRET } from '../test-support/helpers.js';

describe('static frontend serving', () => {
  let relay;
  let staticDir;

  before(async () => {
    staticDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-static-'));
    fs.writeFileSync(
      path.join(staticDir, 'index.html'),
      '<html><link rel="canonical" href="__CANONICAL_ORIGIN__/" />app shell</html>',
    );
    fs.writeFileSync(path.join(staticDir, 'main.js'), 'console.log("js")');
    fs.writeFileSync(path.join(staticDir, 'sw.js'), 'self.skipWaiting()');
    relay = await startServer({
      storage: openStorage(':memory:'),
      powSecret: TEST_SECRET,
      port: 0,
      staticDir,
    });
  });

  after(async () => {
    await relay.close();
    fs.rmSync(staticDir, { recursive: true });
  });

  it('serves existing files', async () => {
    const res = await fetch(`${relay.url}/main.js`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), 'console.log("js")');
  });

  it('falls back to index.html for client-side routes', async () => {
    const res = await fetch(`${relay.url}/join/zryq1q3a58m535p`);
    assert.equal(res.status, 200);
    assert.equal(
      await res.text(),
      `<html><link rel="canonical" href="${relay.url}/" />app shell</html>`,
    );
  });

  it('substitutes the canonical origin from the request', async () => {
    const plain = await fetch(`${relay.url}/`);
    assert.ok((await plain.text()).includes(`href="${relay.url}/"`));

    const proxied = await fetch(`${relay.url}/`, { headers: { 'x-forwarded-proto': 'https' } });
    assert.match(await proxied.text(), /href="https:\/\/127\.0\.0\.1:\d+\/"/);
  });

  it('does not shadow unknown API paths', async () => {
    const res = await fetch(`${relay.url}/api/nope`);
    assert.equal(res.status, 404);
  });

  it('makes the service worker and shell revalidate, other files default', async () => {
    for (const path of ['/sw.js', '/', '/join/zryq1q3a58m535p']) {
      const res = await fetch(`${relay.url}${path}`);
      assert.equal(res.headers.get('cache-control'), 'no-cache', path);
    }
    const asset = await fetch(`${relay.url}/main.js`);
    assert.equal(asset.headers.get('cache-control'), null);
  });
});
