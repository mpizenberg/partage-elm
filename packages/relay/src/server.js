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
import { RETENTION_MS, DEFAULT_APPEND_LIMITS } from './app.js';

const dev = process.argv.includes('--dev');

const SWEEP_INTERVAL_MS = 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
// Groups at or above this fraction of either quota are counted as near-capacity.
const NEAR_QUOTA_FRACTION = 0.8;

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
  const iso = (ms) => new Date(ms).toISOString();

  const purged = storage.purgeIdleGroups(iso(now - RETENTION_MS));
  if (purged > 0) {
    storage.bumpMetric('groups_purged', day, purged);
    console.log(`Purged ${purged} idle group(s)`);
  }

  storage.recordDailyLevels(
    day,
    storage.getFleetLevels({
      idleCutoff: iso(now - RETENTION_MS),
      nearQuotaBytes: Math.floor(DEFAULT_APPEND_LIMITS.maxTotalBytes * NEAR_QUOTA_FRACTION),
      nearQuotaRecords: Math.floor(DEFAULT_APPEND_LIMITS.maxRecords * NEAR_QUOTA_FRACTION),
      actorWindows: [
        { name: 'active_actors_1d', since: iso(now - DAY_MS) },
        { name: 'active_actors_7d', since: iso(now - 7 * DAY_MS) },
        { name: 'active_actors_30d', since: iso(now - 30 * DAY_MS) },
      ],
    }),
  );
}

const { url } = await startServer({
  storage,
  powSecret,
  port: Number(process.env.PORT ?? 8090),
  staticDir: process.env.STATIC_DIR,
});

dailyMaintenance();
setInterval(dailyMaintenance, SWEEP_INTERVAL_MS).unref();

console.log(`Partage relay listening on ${url}${dev ? ' (dev mode)' : ''}`);
