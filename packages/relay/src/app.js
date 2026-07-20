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
// A compact request carries a whole consolidated history in one transaction.
// Whole-log gzip compresses far better than per-record, so this bounds honest
// groups comfortably while keeping the buffered body far below DO memory.
const MAX_COMPACT_BODY_BYTES = 16 * 1024 * 1024;

// A group idle (no authenticated request) longer than this is purged: the
// clients hold the full log and re-push on their next sync (see the retention
// contract in docs/SPECIFICATION.md §14.8).
export const RETENTION_MS = 365 * 24 * 60 * 60 * 1000;
// `last_access` is only rewritten when it is older than this, so a busy group
// costs at most one access write per day rather than one per request.
const ACCESS_TOUCH_INTERVAL_MS = 24 * 60 * 60 * 1000;

// Per-group storage caps (docs/SPECIFICATION.md §14.8). The absolute quota
// bounds total abuse; the monthly rate cap bounds its speed. Honest groups sit
// orders of magnitude below both. Overridable so tests can trip them cheaply.
const DEFAULT_APPEND_LIMITS = {
  maxRecords: 50_000,
  maxTotalBytes: 50 * 1024 * 1024,
  rateBytes: 10 * 1024 * 1024,
  windowMs: 30 * 24 * 60 * 60 * 1000,
};

const encoder = new TextEncoder();

async function sha256Base64Url(text) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(text));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

/** Check a presented group secret against the stored verifier. */
export async function verifyGroupSecret(storage, groupId, secret) {
  const verifier = await storage.getGroupVerifier(groupId);
  if (verifier === null) {
    return 'not_found';
  }
  const presented = await sha256Base64Url(secret);
  return constantTimeEqual(presented, verifier) ? 'ok' : 'unauthorized';
}

/**
 * `storage` interface:
 * - createGroup({groupId, createdBy, authVerifier, powChallenge, created})
 *     → null | 'group_exists'
 * - getGroupVerifier(groupId) → string | null
 * - appendEvent(groupId, {recordId, actorId, eventData, compressed, created}, limits)
 *     → {status: 'ok', seq} | {status: 'quota'} | {status: 'rate', retryAfterMs}
 *     recordId may be null; when it matches an existing record of the group,
 *     that record's seq is returned and nothing is inserted (idempotent push).
 *     A re-push of a counted record is always 'ok'; only genuinely new records
 *     are checked against `limits` and add to the group's counters.
 * - compact(groupId, uptoSeq, records, created, limits)
 *     → {status: 'ok', maxSeq} | {status: 'stale'} | {status: 'quota'}
 *       | {status: 'rate', retryAfterMs}
 *     In one transaction: deletes records with seq ≤ uptoSeq and appends
 *     `records` at fresh higher seqs, skipping ones whose recordId already
 *     survives above the boundary. 'stale' when uptoSeq exceeds the max seq
 *     or covers no records (a lost compaction race). Accounted net against
 *     `limits`: the rate window only pays for growth, never gets refunds.
 * - getGroupStats(groupId)
 *     → {recordCount, totalBytes, bytesThisWindow, windowStart} | null
 * - listEventsSince(groupId, sinceSeq, limit)
 *     → [{seq, actorId, eventData, compressed, created}]
 * - getMaxSeq(groupId) → number (0 when the group has no events)
 *
 * `onAppend(groupId, seq)` is called after each successful event append
 * (used by adapters to notify live subscribers).
 */
export function createApp({ storage, powSecret, onAppend, appendLimits = DEFAULT_APPEND_LIMITS }) {
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
    const groupId = c.req.query('groupId') ?? '';
    if (groupId === '') {
      return c.json({ error: 'groupId query parameter is required' }, 400);
    }
    return c.json(await issueChallenge(powSecret, groupId));
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

    const powError = await verifySolution(powSecret, groupId, body);
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

    return c.json({}, 201);
  });

  // Not a '/api/groups/:id/*' wildcard: the Node adapter mounts its WebSocket
  // route on the same app, and WS auth is query-parameter-based (browsers
  // cannot set headers there) and must never renew last_access.
  const groupAuth = async (c, next) => {
    const auth = c.req.header('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) {
      return c.json({ error: 'Missing bearer token' }, 401);
    }
    const result = await verifyGroupSecret(storage, c.req.param('id'), auth.slice('Bearer '.length));
    if (result === 'not_found') {
      return c.json({ error: 'Group not found' }, 404);
    }
    if (result === 'unauthorized') {
      return c.json({ error: 'Invalid credentials' }, 401);
    }
    const now = Date.now();
    await storage.touchAccess(
      c.req.param('id'),
      new Date(now).toISOString(),
      new Date(now - ACCESS_TOUCH_INTERVAL_MS).toISOString(),
    );
    await next();
  };
  app.use('/api/groups/:id/events', groupAuth);
  app.use('/api/groups/:id/compact', groupAuth);

  app.get('/api/groups/:id/events', async (c) => {
    const sinceRaw = c.req.query('since') ?? '0';
    const since = Number(sinceRaw);
    if (!Number.isInteger(since) || since < 0) {
      return c.json({ error: 'Invalid since cursor' }, 400);
    }
    const rows = await storage.listEventsSince(c.req.param('id'), since, PULL_PAGE_SIZE + 1);
    const hasMore = rows.length > PULL_PAGE_SIZE;
    // The group's total record count rides along so clients can tell when the
    // relay holds far more records than a consolidated history would need —
    // the trigger heuristic for proposing a compaction.
    const recordCount = (await storage.getGroupStats(c.req.param('id')))?.recordCount ?? 0;
    if (rows.length === 0 && since > 0) {
      // A cursor beyond the group's history means the server lost events the
      // client has seen (purge, compaction, resurrection): tell the client to
      // restart its pull from 0 instead of silently reporting "up to date".
      const maxSeq = await storage.getMaxSeq(c.req.param('id'));
      if (since > maxSeq) {
        return c.json({ events: [], hasMore: false, recordCount, resetCursor: true });
      }
    }
    return c.json({ events: hasMore ? rows.slice(0, PULL_PAGE_SIZE) : rows, hasMore, recordCount });
  });

  app.post('/api/groups/:id/events', bodyLimit({ maxSize: MAX_BODY_BYTES }), async (c) => {
    let body;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'Invalid JSON body' }, 400);
    }

    const { actorId, eventData, compressed, recordId } = body;
    if (
      typeof actorId !== 'string' ||
      typeof eventData !== 'string' ||
      typeof compressed !== 'boolean' ||
      actorId === '' ||
      eventData === ''
    ) {
      return c.json({ error: 'actorId, eventData and compressed are required' }, 400);
    }
    if (recordId !== undefined && (typeof recordId !== 'string' || recordId === '' || recordId.length > 200)) {
      return c.json({ error: 'Invalid recordId' }, 400);
    }
    if (eventData.length > MAX_EVENT_DATA_BYTES) {
      return c.json({ error: 'eventData exceeds 1 MB limit' }, 413);
    }

    const groupId = c.req.param('id');
    const result = await storage.appendEvent(
      groupId,
      {
        recordId: recordId ?? null,
        actorId,
        eventData,
        compressed,
        created: new Date().toISOString(),
      },
      appendLimits,
    );
    if (result.status === 'quota') {
      return c.json({ error: 'Group storage quota exceeded — compact or export' }, 507);
    }
    if (result.status === 'rate') {
      return c.json({ error: 'Group data rate limit exceeded' }, 429, {
        'Retry-After': String(Math.ceil(result.retryAfterMs / 1000)),
      });
    }
    onAppend?.(groupId, result.seq);
    return c.json({ seq: result.seq }, 201);
  });

  app.post('/api/groups/:id/compact', bodyLimit({ maxSize: MAX_COMPACT_BODY_BYTES }), async (c) => {
    let body;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'Invalid JSON body' }, 400);
    }

    const { uptoSeq, records } = body;
    if (!Number.isInteger(uptoSeq) || uptoSeq <= 0 || !Array.isArray(records) || records.length === 0) {
      return c.json({ error: 'uptoSeq and a non-empty records array are required' }, 400);
    }
    for (const record of records) {
      if (
        typeof record?.actorId !== 'string' ||
        typeof record?.eventData !== 'string' ||
        typeof record?.compressed !== 'boolean' ||
        record.actorId === '' ||
        record.eventData === ''
      ) {
        return c.json({ error: 'each record requires actorId, eventData and compressed' }, 400);
      }
      if (
        record.recordId !== undefined &&
        (typeof record.recordId !== 'string' || record.recordId === '' || record.recordId.length > 200)
      ) {
        return c.json({ error: 'Invalid recordId' }, 400);
      }
      if (record.eventData.length > MAX_EVENT_DATA_BYTES) {
        return c.json({ error: 'eventData exceeds 1 MB limit' }, 413);
      }
    }

    const groupId = c.req.param('id');
    const result = await storage.compact(
      groupId,
      uptoSeq,
      records.map((record) => ({
        recordId: record.recordId ?? null,
        actorId: record.actorId,
        eventData: record.eventData,
        compressed: record.compressed,
      })),
      new Date().toISOString(),
      appendLimits,
    );
    if (result.status === 'stale') {
      return c.json({ error: 'uptoSeq no longer matches the group history' }, 409);
    }
    if (result.status === 'quota') {
      return c.json({ error: 'Group storage quota exceeded — compact or export' }, 507);
    }
    if (result.status === 'rate') {
      return c.json({ error: 'Group data rate limit exceeded' }, 429, {
        'Retry-After': String(Math.ceil(result.retryAfterMs / 1000)),
      });
    }
    onAppend?.(groupId, result.maxSeq);
    return c.json({ maxSeq: result.maxSeq });
  });

  return app;
}
