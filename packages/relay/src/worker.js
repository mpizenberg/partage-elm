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
import { issueChallenge, verifySolution } from './pow.js';

// Real groupIds are 15-char [a-z0-9] (Infra.IdGen), but the Worker only needs
// to reject shapes that could never name a real group before spending a
// Durable Object on them; a permissive URL-safe bound stays robust to any
// future change in the client id format.
const GROUP_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

function isValidGroupId(id) {
  return typeof id === 'string' && GROUP_ID_PATTERN.test(id);
}

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
      // A dead socket must not abort a committed append nor skip the remaining
      // subscribers, so each send fails in isolation.
      try {
        ws.send(message);
      } catch {
        // Socket already closed; the next fetch will pull the missed seq.
      }
    }
  }

  webSocketMessage() {}

  webSocketClose() {}
}

export default {
  async fetch(request, env) {
    // A relay with no PoW secret would accept unsolved group creations and sign
    // challenges with an empty key: fail loud rather than silently insecure.
    if (!env.POW_SECRET) {
      throw new Error('POW_SECRET is not configured');
    }
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
      if (!isValidGroupId(body.groupId)) {
        return Response.json({ error: 'Invalid groupId' }, { status: 400 });
      }
      // Gate on PoW here, in the stateless Worker, so an unsolved creation never
      // materializes (and bills) a Durable Object. The DO re-checks for the
      // self-host path, which has no Worker in front of it.
      const powError = await verifySolution(env.POW_SECRET, body.groupId, body);
      if (powError !== null) {
        return Response.json({ error: powError }, { status: 400 });
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
      if (!isValidGroupId(groupMatch[1])) {
        return Response.json({ error: 'Invalid groupId' }, { status: 400 });
      }
      return env.GROUP.getByName(groupMatch[1]).fetch(request);
    }

    if (url.pathname.startsWith('/api/')) {
      return Response.json({ error: 'Not found' }, { status: 404 });
    }
    return env.ASSETS.fetch(request);
  },
};
