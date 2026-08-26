import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp } from '../test-support/helpers.js';

describe('security headers', () => {
  it('hardens every response', async () => {
    const res = await makeApp().app.request('/health');
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('referrer-policy'), 'same-origin');
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /frame-ancestors 'none'/);
    assert.match(csp, /script-src 'self'/);
    assert.match(csp, /style-src 'self' 'unsafe-inline'/);
  });

  it('lets the page dial its own host over WebSocket', async () => {
    const res = await makeApp().app.request('/health', { headers: { host: 'relay.example:8090' } });
    assert.match(
      res.headers.get('content-security-policy'),
      /connect-src [^;]*wss:\/\/relay\.example:8090/,
    );
  });

  it('allows the push origin and the feedback frame when configured', async () => {
    const res = await makeApp({
      pushServerUrl: 'https://push.example.com/base',
      feedbackProjectId: 'proj',
    }).app.request('/health');
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /connect-src [^;]*https:\/\/push\.example\.com/);
    assert.match(csp, /frame-src https:\/\/form\.feedback\.one/);
  });

  it('forbids frames entirely when feedback is off', async () => {
    const res = await makeApp().app.request('/health');
    assert.match(res.headers.get('content-security-policy'), /frame-src 'none'/);
  });

  it('gives the admin page its own inline-allowing policy', async () => {
    const res = await makeApp({ adminSecret: 'operator-secret' }).app.request('/admin');
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /script-src 'unsafe-inline'/);
    assert.match(csp, /frame-ancestors 'none'/);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  });
});
