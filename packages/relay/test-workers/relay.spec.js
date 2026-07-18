import { SELF } from 'cloudflare:test';
import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { conformanceSuite } from '../test/conformance.js';
import { createGroup, pushEvent } from '../test/protocol-helpers.js';

const BASE = 'https://relay.test';

const app = {
  request: (path, init) => SELF.fetch(BASE + path, init),
};

conformanceSuite({ describe, it, makeApp: async () => app });

async function connect(groupId, secret) {
  const res = await SELF.fetch(`${BASE}/api/groups/${groupId}/ws?auth=${encodeURIComponent(secret)}`, {
    headers: { Upgrade: 'websocket' },
  });
  return res;
}

describe('worker websocket live updates', () => {
  it('notifies connected clients when an event is appended', async () => {
    const { groupId, secret } = await createGroup(app, { groupId: 'ws1' });
    const res = await connect(groupId, secret);
    assert.equal(res.status, 101);
    const ws = res.webSocket;
    ws.accept();
    const message = new Promise((resolve) => {
      ws.addEventListener('message', (event) => resolve(JSON.parse(event.data)));
    });
    const pushed = await (await pushEvent(app, groupId, secret)).json();
    assert.deepEqual(await message, { seq: pushed.seq });
    ws.close();
  });

  it('rejects a connection with a wrong secret', async () => {
    const { groupId } = await createGroup(app, { groupId: 'ws2' });
    const res = await connect(groupId, 'wrong-secret');
    assert.equal(res.status, 401);
  });

  it('rejects a connection to an unknown group', async () => {
    const res = await connect('nope', 'any');
    assert.equal(res.status, 404);
  });
});
