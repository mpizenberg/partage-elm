import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/node-server.js';
import { openStorage } from '../src/storage-sqlite.js';
import { TEST_SECRET } from './helpers.js';

describe('static frontend serving', () => {
  let relay;
  let staticDir;

  before(async () => {
    staticDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-static-'));
    fs.writeFileSync(path.join(staticDir, 'index.html'), '<html>app shell</html>');
    fs.writeFileSync(path.join(staticDir, 'main.js'), 'console.log("js")');
    relay = await startServer({
      storage: openStorage(':memory:'),
      powSecret: TEST_SECRET,
      port: 0,
      staticDir,
    });
  });

  after(async () => {
    await relay.close();
    fs.rmSync(staticDir, { recursive: true });
  });

  it('serves existing files', async () => {
    const res = await fetch(`${relay.url}/main.js`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), 'console.log("js")');
  });

  it('falls back to index.html for client-side routes', async () => {
    const res = await fetch(`${relay.url}/join/zryq1q3a58m535p`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), '<html>app shell</html>');
  });

  it('does not shadow unknown API paths', async () => {
    const res = await fetch(`${relay.url}/api/nope`);
    assert.equal(res.status, 404);
  });
});
