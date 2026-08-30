import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

function buildServiceWorker(development) {
  execFileSync(process.execPath, ["build-sw.mjs"], {
    env: {
      ...process.env,
      DEV_SERVICE_WORKER: development ? "1" : "",
    },
  });
  return readFileSync("dist/sw.js", "utf8");
}

test("development uses a network-only worker that immediately takes control", () => {
  try {
    const source = buildServiceWorker(true);
    assert.match(source, /"cacheName": "partage-development"/);
    assert.match(source, /"precacheUrls": \[\]/);
    assert.match(source, /"networkOnlyPrefixes": \[\s+"\/"\s+\]/);
    assert.match(source, /event\.waitUntil\(self\.skipWaiting\(\)\)/);
    assert.match(source, /event\.waitUntil\(self\.clients\.claim\(\)\)/);
  } finally {
    buildServiceWorker(false);
  }
});
