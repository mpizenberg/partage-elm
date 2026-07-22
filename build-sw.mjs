import { generateSW } from "./vendor/elm-pwa/js/src/build.js";
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

const precacheUrls = [
  "/",
  // Elm and JS compilation targets
  "/elm.js",
  "/index.js",
  // Web Manifest
  "/manifest.webmanifest",
  // Icons
  "/favicon.svg",
  "/icon.svg",
  "/icon-maskable.svg",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable-512.png",
  "/icon-maskable-180.png",
];

// Version the cache by the precached content: any byte change in a shell asset
// yields a new cacheName, so the activate step evicts the stale cache and the
// new SW installs fresh copies. dist is fully built before this step runs.
const digest = createHash("sha256");
for (const url of precacheUrls) {
  const file = url === "/" ? "dist/index.html" : "dist" + url;
  digest.update(url + "\n");
  digest.update(readFileSync(file));
}
const cacheName = "partage-" + digest.digest("hex").slice(0, 16);

writeFileSync(
  "dist/sw.js",
  generateSW({
    cacheName,
    precacheUrls,
    navigationFallback: "/",
    networkFirstPrefixes: [],
    networkOnlyPrefixes: ["/api/"],
    transformNotification: readFileSync(
      "public/sw-transform-notification.js",
      "utf-8",
    ),
  }),
);
