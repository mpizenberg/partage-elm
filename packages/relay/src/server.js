/**
 * Relay entrypoint: serves the API and (optionally) the built
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
 * - PUSH_SERVER_URL  Push service the frontend addresses, served to it at
 *                runtime via /api/config (optional; unset ships without push).
 * - FEEDBACK_PROJECT_ID  Feedback.one project the in-app form posts to, served
 *                to the frontend via /api/config (optional; unset ships without
 *                the feedback button).
 * - GIT_SHA      Build identity reported by /api/config as `version` (optional;
 *                the image build stamps it, unset reads as an unstamped build).
 * - MIGRATION_TARGET  Deployment this one migrates *to*: enables the frontend's
 *                migration flow and lets its pages address that origin (CSP).
 *                Absolute URL, served via /api/config (optional).
 * - MIGRATION_SOURCE  Deployment users migrate *from*: enables the frontend's
 *                /migrate receiver, which only trusts messages from that
 *                origin. Absolute URL, served via /api/config (optional).
 * - RELAY_READ_ONLY  `true` or `1` freezes writes: group creation, appends and
 *                compactions are refused with 403 `{code:"relay_read_only"}`;
 *                pulls and live updates keep working (optional).
 * - --dev        Development mode: allows a default POW_SECRET.
 *
 * A .env file in the working directory supplies any of the above, so a local
 * run needs no exported variables. The environment wins over the file, so a
 * deployment's own settings can never be shadowed by one left lying around.
 */

import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { startServer } from './node-server.js';
import { openStorage } from './storage.js';
import { LANDING_REFERRER_LIMIT, RETENTION_MS, fleetLevelParams } from './app.js';

try {
  process.loadEnvFile();
} catch {
  // No .env here: every setting comes from the environment or its default.
}

const dev = process.argv.includes('--dev');

const SWEEP_INTERVAL_MS = 24 * 60 * 60 * 1000;
const SHUTDOWN_TIMEOUT_MS = 10 * 1000;

const powSecret = process.env.POW_SECRET ?? (dev ? 'partage-pow-secret-dev-only' : null);
if (powSecret === null) {
  console.error('POW_SECRET is required (or run with --dev for local development)');
  process.exit(1);
}

const dbPath = process.env.RELAY_DB ?? './data/relay.db';
mkdirSync(dirname(dbPath), { recursive: true });

const storage = openStorage(dbPath);

// Runs at startup and once a day: purge idle groups, finalize completed landing
// days, and snapshot current fleet levels for dashboard trends. A failed sweep
// must not take the relay down with it; the next run retries.
function dailyMaintenance() {
  const now = Date.now();
  const day = new Date(now).toISOString().slice(0, 10);

  try {
    const purged = storage.purgeIdleGroups(new Date(now - RETENTION_MS).toISOString());
    if (purged > 0) {
      storage.bumpMetric('groups_purged', day, purged);
      console.log(`Purged ${purged} idle group(s)`);
    }

    storage.finalizeLandingReferrers(day, LANDING_REFERRER_LIMIT);
    storage.recordDailyLevels(day, storage.getFleetLevels(fleetLevelParams(now)));
  } catch (err) {
    console.error('Daily maintenance failed', err);
  }
}

const { url, close } = await startServer({
  storage,
  powSecret,
  port: Number(process.env.PORT ?? 8090),
  staticDir: process.env.STATIC_DIR,
  adminSecret: process.env.ADMIN_SECRET ?? null,
  adminStorageBudgetBytes: process.env.ADMIN_STORAGE_BUDGET_BYTES
    ? Number(process.env.ADMIN_STORAGE_BUDGET_BYTES)
    : null,
  pushServerUrl: process.env.PUSH_SERVER_URL ?? '',
  feedbackProjectId: process.env.FEEDBACK_PROJECT_ID ?? '',
  version: process.env.GIT_SHA ?? '',
  migrationTarget: process.env.MIGRATION_TARGET ?? '',
  migrationSource: process.env.MIGRATION_SOURCE ?? '',
  readOnly: ['true', '1'].includes(process.env.RELAY_READ_ONLY ?? ''),
  dev,
});

dailyMaintenance();
setInterval(dailyMaintenance, SWEEP_INTERVAL_MS).unref();

console.log(`Partage relay listening on ${url}${dev ? ' (dev mode)' : ''}`);

// Orchestrators stop a container by sending SIGTERM and killing it if it lingers.
// Drain and close the server and the SQLite handle so no request commits an event
// without its accounting; a stuck close must not wedge the container, so a bounded
// timer forces exit.
let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  console.log(`Received ${signal}, shutting down`);
  const forceExit = setTimeout(() => {
    console.error(`Shutdown exceeded ${SHUTDOWN_TIMEOUT_MS}ms, forcing exit`);
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExit.unref();
  try {
    await close();
    storage.close();
    console.log('Shutdown complete');
    process.exit(0);
  } catch (err) {
    console.error('Error during shutdown', err);
    process.exit(1);
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
