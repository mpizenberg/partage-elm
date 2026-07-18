/**
 * Portable relay core: a zero-knowledge, append-only encrypted event relay.
 *
 * The server never sees group content — only groupId, actorId (a public-key
 * hash), and opaque encrypted blobs. Auth is group-level: the bearer secret is
 * derived client-side from the group key; the server stores only its SHA-256
 * hash (set once at group creation) and compares in constant time.
 *
 * Platform-agnostic (web-standard APIs only): the same app runs on Node and
 * Cloudflare Workers, with all platform behavior behind the `storage`
 * interface (see storage-sqlite.js for the reference implementation).
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { bodyLimit } from 'hono/body-limit';
import { issueChallenge, verifySolution, constantTimeEqual } from './pow.js';

export const PULL_PAGE_SIZE = 200;
const MAX_EVENT_DATA_BYTES = 1024 * 1024;
const MAX_BODY_BYTES = MAX_EVENT_DATA_BYTES + 16 * 1024;

const encoder = new TextEncoder();

async function sha256Base64Url(text) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(text));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

/**
 * `storage` interface:
 * - createGroup({groupId, createdBy, authVerifier, powChallenge, created})
 *     → null | 'group_exists' | 'challenge_used'
 * - getGroupVerifier(groupId) → string | null
 * - appendEvent(groupId, {actorId, eventData, compressed, created}) → seq
 * - listEventsSince(groupId, sinceSeq, limit)
 *     → [{seq, actorId, eventData, compressed, created}]
 *
 * `onAppend(groupId, seq)` is called after each successful event append
 * (used by adapters to notify live subscribers).
 */
export function createApp({ storage, powSecret, onAppend }) {
  const app = new Hono();

  app.use(
    cors({
      origin: (origin) => origin,
      allowHeaders: ['Authorization', 'Content-Type'],
    }),
  );
  app.use(async (c, next) => {
    await next();
    c.header('Timing-Allow-Origin', '*');
  });

  app.get('/api/pow/challenge', async (c) => {
    return c.json(await issueChallenge(powSecret));
  });

  app.post('/api/groups', bodyLimit({ maxSize: 16 * 1024 }), async (c) => {
    let body;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'Invalid JSON body' }, 400);
    }

    const { groupId, createdBy, authVerifier } = body;
    if (
      typeof groupId !== 'string' ||
      typeof createdBy !== 'string' ||
      typeof authVerifier !== 'string' ||
      groupId === '' ||
      createdBy === '' ||
      authVerifier === ''
    ) {
      return c.json({ error: 'groupId, createdBy and authVerifier are required' }, 400);
    }

    const powError = await verifySolution(powSecret, body);
    if (powError !== null) {
      return c.json({ error: powError }, 400);
    }

    const conflict = await storage.createGroup({
      groupId,
      createdBy,
      authVerifier,
      powChallenge: body.pow_challenge,
      created: new Date().toISOString(),
    });
    if (conflict === 'group_exists') {
      return c.json({ error: 'Group already exists' }, 409);
    }
    if (conflict === 'challenge_used') {
      return c.json({ error: 'PoW verification failed: Challenge already used' }, 409);
    }

    return c.json({}, 201);
  });

  app.use('/api/groups/:id/events', async (c, next) => {
    const auth = c.req.header('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) {
      return c.json({ error: 'Missing bearer token' }, 401);
    }
    const verifier = await storage.getGroupVerifier(c.req.param('id'));
    if (verifier === null) {
      return c.json({ error: 'Group not found' }, 404);
    }
    const presented = await sha256Base64Url(auth.slice('Bearer '.length));
    if (!constantTimeEqual(presented, verifier)) {
      return c.json({ error: 'Invalid credentials' }, 401);
    }
    await next();
  });

  app.get('/api/groups/:id/events', async (c) => {
    const sinceRaw = c.req.query('since') ?? '0';
    const since = Number(sinceRaw);
    if (!Number.isInteger(since) || since < 0) {
      return c.json({ error: 'Invalid since cursor' }, 400);
    }
    const rows = await storage.listEventsSince(c.req.param('id'), since, PULL_PAGE_SIZE + 1);
    const hasMore = rows.length > PULL_PAGE_SIZE;
    return c.json({ events: hasMore ? rows.slice(0, PULL_PAGE_SIZE) : rows, hasMore });
  });

  app.post('/api/groups/:id/events', bodyLimit({ maxSize: MAX_BODY_BYTES }), async (c) => {
    let body;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'Invalid JSON body' }, 400);
    }

    const { actorId, eventData, compressed } = body;
    if (
      typeof actorId !== 'string' ||
      typeof eventData !== 'string' ||
      typeof compressed !== 'boolean' ||
      actorId === '' ||
      eventData === ''
    ) {
      return c.json({ error: 'actorId, eventData and compressed are required' }, 400);
    }
    if (eventData.length > MAX_EVENT_DATA_BYTES) {
      return c.json({ error: 'eventData exceeds 1 MB limit' }, 413);
    }

    const groupId = c.req.param('id');
    const seq = await storage.appendEvent(groupId, {
      actorId,
      eventData,
      compressed,
      created: new Date().toISOString(),
    });
    onAppend?.(groupId, seq);
    return c.json({ seq }, 201);
  });

  return app;
}
