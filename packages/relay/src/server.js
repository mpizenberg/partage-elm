/**
 * Self-host entrypoint: serves the relay API and (optionally) the built
 * frontend from one Node process.
 *
 * Configuration:
 * - POW_SECRET   HMAC secret for PoW challenges. Required, except with --dev.
 * - RELAY_DB     SQLite file path (default ./data/relay.db).
 * - PORT         Listen port (default 8090).
 * - STATIC_DIR   Directory with the built frontend to serve (optional).
 * - --dev        Development mode: allows a default POW_SECRET.
 */

import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { createApp } from './app.js';
import { openStorage } from './storage-sqlite.js';

const dev = process.argv.includes('--dev');

const powSecret = process.env.POW_SECRET ?? (dev ? 'partage-pow-secret-dev-only' : null);
if (powSecret === null) {
  console.error('POW_SECRET is required (or run with --dev for local development)');
  process.exit(1);
}

const dbPath = process.env.RELAY_DB ?? './data/relay.db';
mkdirSync(dirname(dbPath), { recursive: true });
const storage = openStorage(dbPath);

const app = createApp({ storage, powSecret });

if (process.env.STATIC_DIR) {
  app.use('/*', serveStatic({ root: process.env.STATIC_DIR }));
}

const port = Number(process.env.PORT ?? 8090);
serve({ fetch: app.fetch, port }, () => {
  console.log(`Partage relay listening on http://127.0.0.1:${port}${dev ? ' (dev mode)' : ''}`);
});
