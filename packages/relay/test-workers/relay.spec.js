import { SELF, env, runInDurableObject, runDurableObjectAlarm } from 'cloudflare:test';
import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { conformanceSuite } from '../test/conformance.js';
import { createGroup, pushEvent, pullEvents } from '../test/protocol-helpers.js';

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

describe('worker inactivity retention', () => {
  it('purges an idle group when its DO alarm fires', async () => {
    const { groupId, secret } = await createGroup(app, { groupId: 'idle-do' });
    await pushEvent(app, groupId, secret);

    const stub = env.GROUP.getByName(groupId);
    await runInDurableObject(stub, (instance) => {
      instance.storage.touchAccess(groupId, '2000-01-01T00:00:00.000Z', '2999-01-01T00:00:00.000Z');
    });
    assert.equal(await runDurableObjectAlarm(stub), true);

    // Purged group answers 404 — the client's next sync resurrects it.
    assert.equal((await pullEvents(app, groupId, secret)).status, 404);
  });

  it('re-arms the alarm for a group still within the window', async () => {
    const { groupId, secret } = await createGroup(app, { groupId: 'active-do' });
    const stub = env.GROUP.getByName(groupId);
    assert.equal(await runDurableObjectAlarm(stub), true);

    // Recently accessed → survives and stays reachable.
    assert.equal((await pullEvents(app, groupId, secret)).status, 200);
  });
});
