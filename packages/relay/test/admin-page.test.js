import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp } from './helpers.js';

const ADMIN = 'operator-secret';

describe('admin dashboard page', () => {
  it('is absent (404) unless ADMIN_SECRET is configured', async () => {
    const { app } = makeApp();
    assert.equal((await app.request('/admin')).status, 404);
  });

  it('serves a self-contained operator page when configured', async () => {
    const { app } = makeApp({ adminSecret: ADMIN });
    const res = await app.request('/admin');
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') ?? '', /text\/html/);
    const html = await res.text();
    assert.match(html, /\/api\/admin\/summary/); // wires to the data endpoint
    assert.match(html, /sessionStorage/); // secret held only in the tab session
    assert.doesNotMatch(html, /<script[^>]*\ssrc=/i); // no external scripts
    assert.doesNotMatch(html, /<link\b/i); // no external stylesheets
  });

  it('serves the shell without a bearer — only the data needs the secret', async () => {
    const { app } = makeApp({ adminSecret: ADMIN });
    assert.equal((await app.request('/admin')).status, 200);
  });
});
