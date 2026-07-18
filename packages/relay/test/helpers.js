import { createApp } from '../src/app.js';
import { openStorage } from '../src/storage-sqlite.js';
import { TEST_SECRET } from './protocol-helpers.js';

export * from './protocol-helpers.js';

export function makeApp(overrides = {}) {
  const storage = openStorage(':memory:');
  const app = createApp({ storage, powSecret: TEST_SECRET, ...overrides });
  return { app, storage };
}
