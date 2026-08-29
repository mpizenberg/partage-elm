import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/node-server.js';
import { openStorage } from '../src/storage.js';
import { TEST_SECRET } from '../test-support/helpers.js';

function writeEntryFiles(dir) {
  fs.writeFileSync(
    path.join(dir, 'app.html'),
    '<html><meta property="og:url" content="__CANONICAL_ORIGIN__/" />app shell</html>',
  );
  for (const language of ['en', 'fr']) {
    const languageDir = path.join(dir, language);
    fs.mkdirSync(languageDir);
    fs.writeFileSync(
      path.join(languageDir, 'index.html'),
      `<html lang="${language}"><link rel="canonical" href="__CANONICAL_ORIGIN__/${language}/" />${language} home</html>`,
    );
  }
}

function writeDiscoveryFiles(dir) {
  fs.writeFileSync(
    path.join(dir, 'robots.txt'),
    'User-agent: *\nAllow: /\nSitemap: __CANONICAL_ORIGIN__/sitemap.xml\n',
  );
  fs.writeFileSync(
    path.join(dir, 'sitemap.xml'),
    '<urlset><url><loc>__CANONICAL_ORIGIN__/en/</loc></url><url><loc>__CANONICAL_ORIGIN__/fr/</loc></url></urlset>',
  );
}

describe('static frontend serving', () => {
  let relay;
  let staticDir;
  let storage;

  before(async () => {
    staticDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-static-'));
    writeEntryFiles(staticDir);
    fs.writeFileSync(path.join(staticDir, 'main.js'), 'console.log("js")');
    fs.writeFileSync(
      path.join(staticDir, 'sw.js'),
      'var CACHE = "partage-abc-__CONFIG_DIGEST__";',
    );
    writeDiscoveryFiles(staticDir);
    storage = openStorage(':memory:');
    relay = await startServer({
      storage,
      powSecret: TEST_SECRET,
      port: 0,
      staticDir,
    });
  });

  after(async () => {
    await relay.close();
    storage.close();
    fs.rmSync(staticDir, { recursive: true });
  });

  it('refuses to start from a build without its service worker', async () => {
    const incompleteDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-incomplete-static-'));
    writeEntryFiles(incompleteDir);
    writeDiscoveryFiles(incompleteDir);
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

  it('falls back to app.html for client-side routes', async () => {
    const res = await fetch(`${relay.url}/join/zryq1q3a58m535p`);
    assert.equal(res.status, 200);
    assert.equal(
      await res.text(),
      `<html><meta property="og:url" content="${relay.url}/" />app shell</html>`,
    );
  });

  it('substitutes the canonical origin in the shell, home, and crawler files', async () => {
    const plain = await fetch(`${relay.url}/app.html`);
    assert.ok((await plain.text()).includes(`content="${relay.url}/"`));

    const proxiedHeaders = { 'x-forwarded-proto': 'https' };
    const proxied = await fetch(`${relay.url}/app.html`, { headers: proxiedHeaders });
    const expectedOrigin = relay.url.replace('http:', 'https:');
    assert.ok((await proxied.text()).includes(`content="${expectedOrigin}/"`));

    const home = await fetch(`${relay.url}/fr/`, { headers: proxiedHeaders });
    assert.equal(home.headers.get('content-language'), 'fr');
    assert.ok((await home.text()).includes(`href="${expectedOrigin}/fr/"`));

    const robots = await fetch(`${relay.url}/robots.txt`, { headers: proxiedHeaders });
    assert.equal(
      await robots.text(),
      `User-agent: *\nAllow: /\nSitemap: ${expectedOrigin}/sitemap.xml\n`,
    );

    const sitemap = await fetch(`${relay.url}/sitemap.xml`, { headers: proxiedHeaders });
    assert.equal(sitemap.headers.get('content-type'), 'application/xml; charset=utf-8');
    assert.equal(
      await sitemap.text(),
      `<urlset><url><loc>${expectedOrigin}/en/</loc></url><url><loc>${expectedOrigin}/fr/</loc></url></urlset>`,
    );
  });

  it('negotiates the static home language', async () => {
    const french = await fetch(`${relay.url}/`, {
      headers: { 'accept-language': 'en;q=0.5, fr-FR;q=0.9' },
      redirect: 'manual',
    });
    assert.equal(french.status, 302);
    assert.equal(french.headers.get('location'), '/fr/');
    assert.match(french.headers.get('vary'), /Accept-Language/);

    const fallback = await fetch(`${relay.url}/`, {
      headers: { 'accept-language': 'de-DE' },
      redirect: 'manual',
    });
    assert.equal(fallback.headers.get('location'), '/en/');

    const removedIndex = await fetch(`${relay.url}/index.html`);
    assert.equal(removedIndex.status, 404);
  });

  it('does not shadow unknown API paths', async () => {
    const res = await fetch(`${relay.url}/api/nope`);
    assert.equal(res.status, 404);
  });

  it('makes the service worker and shell revalidate, other files default', async () => {
    for (const path of [
      '/sw.js',
      '/app.html',
      '/robots.txt',
      '/sitemap.xml',
      '/',
      '/en/',
      '/join/zryq1q3a58m535p',
    ]) {
      const res = await fetch(`${relay.url}${path}`);
      assert.equal(res.headers.get('cache-control'), 'no-cache', path);
    }
    const asset = await fetch(`${relay.url}/main.js`);
    assert.equal(asset.headers.get('cache-control'), null);
  });

  it('counts only external or no-referrer HTML landings', async () => {
    const day = new Date().toISOString().slice(0, 10);
    const before = storage.getLandingWindow({ firstDay: day, lastDay: day, limit: 10 });
    await fetch(`${relay.url}/en/`, { headers: { 'sec-fetch-dest': 'document' } });
    await fetch(`${relay.url}/en/`, {
      headers: { 'sec-fetch-dest': 'document', referer: 'https://news.ycombinator.com/item?id=1' },
    });
    await fetch(`${relay.url}/en/`, {
      headers: { 'sec-fetch-dest': 'document', referer: `${relay.url}/groups` },
    });
    await fetch(`${relay.url}/en/`, {
      headers: { 'sec-fetch-dest': 'document', referer: 'http://127.0.0.1:1/source' },
    });
    await fetch(`${relay.url}/en/`, {
      headers: {
        'sec-fetch-dest': 'document',
        'x-forwarded-proto': 'https',
        referer: `${relay.url.replace('http:', 'https:')}/groups`,
      },
    });
    await fetch(`${relay.url}/en/`, { headers: { 'sec-fetch-mode': 'cors', 'sec-fetch-dest': 'empty' } });
    await fetch(`${relay.url}/main.js`, { headers: { referer: 'https://www.reddit.com/r/opensource/' } });
    await fetch(`${relay.url}/api/config`, { headers: { referer: 'https://www.reddit.com/r/opensource/' } });

    const after = storage.getLandingWindow({ firstDay: day, lastDay: day, limit: 10 });
    assert.equal(after.total, before.total + 3);
    assert.deepEqual(after.referrers.find((row) => row.hostname === 'news.ycombinator.com'), {
      hostname: 'news.ycombinator.com',
      requests: 1,
    });
    assert.deepEqual(after.referrers.find((row) => row.hostname === '127.0.0.1'), {
      hostname: '127.0.0.1',
      requests: 1,
    });
  });
});

describe('service worker cache identity', () => {
  const serveSw = async (config) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-sw-'));
    writeEntryFiles(dir);
    fs.writeFileSync(path.join(dir, 'sw.js'), 'var CACHE = "partage-abc-__CONFIG_DIGEST__";');
    writeDiscoveryFiles(dir);
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
