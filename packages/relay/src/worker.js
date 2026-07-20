/**
 * Cloudflare adapter: a Worker routing each group's traffic to its own
 * Durable Object (idFromName(groupId)), which hosts the portable app over
 * DO SQLite plus hibernating WebSockets. Non-API paths fall through to the
 * static frontend (Workers assets), so the hosted instance is same-origin —
 * cross-origin CORS (handled inside the portable app) never applies to the
 * two routes answered directly by the Worker.
 *
 * Configuration: POW_SECRET is a Worker secret (`wrangler secret put`).
 */

import { DurableObject } from 'cloudflare:workers';
import { createApp, verifyGroupSecret, RETENTION_MS } from './app.js';
import { createDoStorage } from './storage-do.js';
import { issueChallenge } from './pow.js';

export class GroupDo extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.storage = createDoStorage(ctx.storage.sql);
    this.app = createApp({
      storage: this.storage,
      powSecret: env.POW_SECRET,
      onAppend: (_groupId, seq) => this.broadcast(seq),
    });
  }

  // Keep a retention sweep scheduled for the lifetime of the group. The first
  // request to hit the DO arms it; the alarm re-arms itself while the group
  // stays active and purges it once idle past the window.
  async ensureAlarm() {
    if ((await this.ctx.storage.getAlarm()) === null) {
      await this.ctx.storage.setAlarm(Date.now() + RETENTION_MS);
    }
  }

  async alarm() {
    const group = this.storage.soleGroup();
    if (group === null) {
      return;
    }
    const purgeAt = Date.parse(group.lastAccess) + RETENTION_MS;
    if (Date.now() >= purgeAt) {
      this.storage.purgeIdleGroups(new Date(Date.now() - RETENTION_MS).toISOString());
    } else {
      await this.ctx.storage.setAlarm(purgeAt);
    }
  }

  async fetch(request) {
    await this.ensureAlarm();
    const url = new URL(request.url);
    if (url.pathname.endsWith('/ws')) {
      const groupId = url.pathname.split('/')[3];
      const result = await verifyGroupSecret(this.storage, groupId, url.searchParams.get('auth') ?? '');
      if (result === 'not_found') {
        return Response.json({ error: 'Group not found' }, { status: 404 });
      }
      if (result === 'unauthorized') {
        return Response.json({ error: 'Invalid credentials' }, { status: 401 });
      }
      if (request.headers.get('Upgrade') !== 'websocket') {
        return Response.json({ error: 'Expected a WebSocket upgrade' }, { status: 426 });
      }
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    return this.app.fetch(request);
  }

  broadcast(seq) {
    const message = JSON.stringify({ seq });
    for (const ws of this.ctx.getWebSockets()) {
      ws.send(message);
    }
  }

  webSocketMessage() {}

  webSocketClose() {}
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api/pow/challenge') {
      const groupId = url.searchParams.get('groupId') ?? '';
      if (groupId === '') {
        return Response.json({ error: 'groupId query parameter is required' }, { status: 400 });
      }
      return Response.json(await issueChallenge(env.POW_SECRET, groupId));
    }

    if (url.pathname === '/api/groups' && request.method === 'POST') {
      let body;
      try {
        body = await request.json();
      } catch {
        return Response.json({ error: 'Invalid JSON body' }, { status: 400 });
      }
      if (typeof body.groupId !== 'string' || body.groupId === '') {
        return Response.json({ error: 'groupId, createdBy and authVerifier are required' }, { status: 400 });
      }
      return env.GROUP.getByName(body.groupId).fetch(
        new Request(request.url, {
          method: 'POST',
          headers: request.headers,
          body: JSON.stringify(body),
        }),
      );
    }

    const groupMatch = url.pathname.match(/^\/api\/groups\/([^/]+)\//);
    if (groupMatch) {
      return env.GROUP.getByName(groupMatch[1]).fetch(request);
    }

    if (url.pathname.startsWith('/api/')) {
      return Response.json({ error: 'Not found' }, { status: 404 });
    }
    return env.ASSETS.fetch(request);
  },
};
