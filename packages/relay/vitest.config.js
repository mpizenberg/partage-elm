import { cloudflareTest } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: './test-workers/wrangler.test.jsonc' },
      miniflare: {
        bindings: { POW_SECRET: 'test-pow-secret' },
      },
    }),
  ],
  test: {
    include: ['test-workers/**/*.spec.js'],
    // Each request boots through workerd and a per-group Durable Object, and the
    // whole suite shares one Miniflare instance; the 5s default is too tight for
    // the heaviest cases on a loaded CI runner.
    testTimeout: 30_000,
  },
});
