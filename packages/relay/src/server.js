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
import { startServer } from './node-server.js';
import { openStorage } from './storage-sqlite.js';
import { RETENTION_MS } from './app.js';

const dev = process.argv.includes('--dev');

const SWEEP_INTERVAL_MS = 24 * 60 * 60 * 1000;

const powSecret = process.env.POW_SECRET ?? (dev ? 'partage-pow-secret-dev-only' : null);
if (powSecret === null) {
  console.error('POW_SECRET is required (or run with --dev for local development)');
  process.exit(1);
}

const dbPath = process.env.RELAY_DB ?? './data/relay.db';
mkdirSync(dirname(dbPath), { recursive: true });

const storage = openStorage(dbPath);

function sweepIdleGroups() {
  const purged = storage.purgeIdleGroups(new Date(Date.now() - RETENTION_MS).toISOString());
  if (purged > 0) {
    console.log(`Purged ${purged} idle group(s)`);
  }
}

const { url } = await startServer({
  storage,
  powSecret,
  port: Number(process.env.PORT ?? 8090),
  staticDir: process.env.STATIC_DIR,
});

sweepIdleGroups();
setInterval(sweepIdleGroups, SWEEP_INTERVAL_MS).unref();

console.log(`Partage relay listening on ${url}${dev ? ' (dev mode)' : ''}`);
