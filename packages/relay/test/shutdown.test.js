import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openStorage } from '../src/storage.js';

const serverPath = fileURLToPath(new URL('../src/server.js', import.meta.url));

// Spawn the entrypoint on an ephemeral port and its own temp database, and
// resolve once it logs that it is listening (or reject if it dies first).
function startProcess(dbPath) {
  const child = spawn('node', [serverPath, '--dev'], {
    env: { ...process.env, RELAY_DB: dbPath, PORT: '0' },
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  const listening = new Promise((resolve, reject) => {
    let out = '';
    child.stdout.on('data', (chunk) => {
      out += chunk.toString();
      if (out.includes('listening')) {
        resolve();
      }
    });
    child.on('exit', (code) => reject(new Error(`server exited early with code ${code}`)));
  });
  return { child, listening };
}

describe('graceful shutdown', () => {
  it('exits 0 on SIGTERM and leaves the database openable', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-shutdown-'));
    const dbPath = path.join(dir, 'relay.db');
    const { child, listening } = startProcess(dbPath);
    await listening;

    const exited = new Promise((resolve) => child.on('exit', (code) => resolve(code)));
    child.kill('SIGTERM');
    assert.equal(await exited, 0);

    // A clean close checkpoints the WAL; the file reopens without recovery.
    openStorage(dbPath).close();

    fs.rmSync(dir, { recursive: true, force: true });
  });
});
