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
    fs.writeFileSync(
      path.join(staticDir, 'sw.js'),
      'var CACHE = "partage-abc-__CONFIG_DIGEST__";',
    );
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

  it('refuses to start from a build without its service worker', async () => {
    const incompleteDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-incomplete-static-'));
    fs.writeFileSync(path.join(incompleteDir, 'index.html'), 'app shell');
    let unexpectedlyStarted;

    try {
      await assert.rejects(
        async () => {
          unexpectedlyStarted = await startServer({
            storage: openStorage(':memory:'),
            powSecret: TEST_SECRET,
            port: 0,
            staticDir: incompleteDir,
          });
        },
        /sw\.js/,
      );
    } finally {
      await unexpectedlyStarted?.close();
      fs.rmSync(incompleteDir, { recursive: true });
    }
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

describe('service worker cache identity', () => {
  const serveSw = async (config) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-sw-'));
    fs.writeFileSync(path.join(dir, 'index.html'), 'app shell');
    fs.writeFileSync(path.join(dir, 'sw.js'), 'var CACHE = "partage-abc-__CONFIG_DIGEST__";');
    const relay = await startServer({
      storage: openStorage(':memory:'),
      powSecret: TEST_SECRET,
      port: 0,
      staticDir: dir,
      ...config,
    });
    const source = await (await fetch(`${relay.url}/sw.js`)).text();
    await relay.close();
    fs.rmSync(dir, { recursive: true });
    return source;
  };

  it('stamps the cache name with the configuration, never the placeholder', async () => {
    assert.match(await serveSw({}), /^var CACHE = "partage-abc-[0-9a-f]{16}";$/);
  });

  it('moves the cache when a setting rewrites the CSP', async () => {
    // Clients precache the shell with its headers, so a CSP that predates the
    // setting has to expire with the cache holding it — otherwise turning the
    // setting on leaves every existing client unable to reach what it allows.
    const unset = await serveSw({});
    assert.notEqual(await serveSw({ migrationTarget: 'https://new.example.com' }), unset);
    assert.notEqual(await serveSw({ pushServerUrl: 'https://push.example.com' }), unset);
    assert.notEqual(await serveSw({ feedbackProjectId: 'proj_123' }), unset);
  });

  it('leaves the cache alone for settings no cached header carries', async () => {
    // The freeze and the receiver reach the app over /api/config, which is
    // never cached, so re-precaching every client for them is pure churn.
    const unset = await serveSw({});
    assert.equal(await serveSw({ readOnly: true }), unset);
    assert.equal(await serveSw({ migrationSource: 'https://old.example.com' }), unset);
  });
});
