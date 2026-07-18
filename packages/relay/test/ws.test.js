import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../src/node-server.js';
import { openStorage } from '../src/storage-sqlite.js';
import { TEST_SECRET, createGroup, pushEvent } from './helpers.js';

function fetchApp(url) {
  return {
    request: (path, init) => fetch(url + path, init),
  };
}

function connect(url, groupId, secret) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${url.replace('http', 'ws')}/api/groups/${groupId}/ws?auth=${secret}`);
    ws.onopen = () => resolve(ws);
    ws.onerror = () => reject(new Error('connection failed'));
  });
}

function nextMessage(ws, timeoutMs = 2000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out waiting for message')), timeoutMs);
    ws.onmessage = (event) => {
      clearTimeout(timer);
      resolve(JSON.parse(event.data));
    };
  });
}

describe('websocket live updates', () => {
  let relay;
  let app;

  before(async () => {
    relay = await startServer({ storage: openStorage(':memory:'), powSecret: TEST_SECRET, port: 0 });
    app = fetchApp(relay.url);
  });

  after(() => relay.close());

  it('notifies connected clients when an event is appended', async () => {
    const { groupId, secret } = await createGroup(app, { groupId: 'ws1' });
    const ws = await connect(relay.url, groupId, secret);
    const message = nextMessage(ws);
    const pushed = await (await pushEvent(app, groupId, secret)).json();
    assert.deepEqual(await message, { seq: pushed.seq });
    ws.close();
  });

  it('does not notify clients of other groups', async () => {
    const a = await createGroup(app, { groupId: 'wsa' });
    const b = await createGroup(app, { groupId: 'wsb' });
    const wsA = await connect(relay.url, a.groupId, a.secret);
    const wsB = await connect(relay.url, b.groupId, b.secret);
    const messageA = nextMessage(wsA);
    const messageB = nextMessage(wsB, 500);
    const pushed = await (await pushEvent(app, a.groupId, a.secret)).json();
    assert.deepEqual(await messageA, { seq: pushed.seq });
    await assert.rejects(messageB, /timed out/);
    wsA.close();
    wsB.close();
  });

  it('rejects a connection with a wrong secret', async () => {
    const { groupId } = await createGroup(app, { groupId: 'ws2' });
    await assert.rejects(connect(relay.url, groupId, 'wrong-secret'), /connection failed/);
  });

  it('rejects a connection to an unknown group', async () => {
    await assert.rejects(connect(relay.url, 'nope', 'any'), /connection failed/);
  });

  it('stops notifying after the client disconnects', async () => {
    const { groupId, secret } = await createGroup(app, { groupId: 'ws3' });
    const ws = await connect(relay.url, groupId, secret);
    await new Promise((resolve) => {
      ws.onclose = resolve;
      ws.close();
    });
    const res = await pushEvent(app, groupId, secret);
    assert.equal(res.status, 201);
  });
});
