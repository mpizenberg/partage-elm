import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { conformanceSuite } from './conformance.js';
import { makeApp, createGroup, pushEvent } from './helpers.js';

conformanceSuite({ describe, it, makeApp: async () => makeApp().app });

describe('node adapter specifics', () => {
  it('notifies onAppend with the new seq', async () => {
    const notified = [];
    const { app } = makeApp({ onAppend: (groupId, seq) => notified.push([groupId, seq]) });
    const { groupId, secret } = await createGroup(app);
    await pushEvent(app, groupId, secret);
    assert.deepEqual(notified, [[groupId, 1]]);
  });
});
