/**
 * Self-host entrypoint: serves the relay API and (optionally) the built
 * frontend from one Node process.
 *
 * Configuration:
 * - POW_SECRET   HMAC secret for PoW challenges. Required, except with --dev.
 * - RELAY_DB     SQLite file path (default ./data/relay.db).
 * - PORT         Listen port (default 8090).
 * - STATIC_DIR   Directory with the built frontend to serve (optional).
 * - ADMIN_SECRET Bearer secret for the operator dashboard endpoint (optional;
 *                the endpoint is absent unless set).
 * - ADMIN_STORAGE_BUDGET_BYTES  Flags the storage-over-budget alert when total
 *                bytes exceed it (optional).
 * - --dev        Development mode: allows a default POW_SECRET.
 */

import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { startServer } from './node-server.js';
import { openStorage } from './storage-sqlite.js';
import { RETENTION_MS, fleetLevelParams } from './app.js';

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

// Runs at startup and once a day: purge groups idle past the retention window,
// then snapshot the fleet's current levels so the operator dashboard can trend
// state that the live tables only ever hold for the present.
function dailyMaintenance() {
  const now = Date.now();
  const day = new Date(now).toISOString().slice(0, 10);

  const purged = storage.purgeIdleGroups(new Date(now - RETENTION_MS).toISOString());
  if (purged > 0) {
    storage.bumpMetric('groups_purged', day, purged);
    console.log(`Purged ${purged} idle group(s)`);
  }

  storage.recordDailyLevels(day, storage.getFleetLevels(fleetLevelParams(now)));
}

const { url } = await startServer({
  storage,
  powSecret,
  port: Number(process.env.PORT ?? 8090),
  staticDir: process.env.STATIC_DIR,
  adminSecret: process.env.ADMIN_SECRET ?? null,
  adminStorageBudgetBytes: process.env.ADMIN_STORAGE_BUDGET_BYTES
    ? Number(process.env.ADMIN_STORAGE_BUDGET_BYTES)
    : null,
});

dailyMaintenance();
setInterval(dailyMaintenance, SWEEP_INTERVAL_MS).unref();

console.log(`Partage relay listening on ${url}${dev ? ' (dev mode)' : ''}`);
