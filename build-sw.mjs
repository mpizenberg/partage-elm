import { generateSW } from "./vendor/elm-pwa/js/src/build.js";
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

const precacheUrls = [
  "/app.html",
  // Elm and JS compilation targets
  "/elm.js",
  "/index.js",
  // Feedback SDK: never executed until someone opens the form, but cached with
  // the shell so opening it is not a cold fetch.
  "/feedback-one.js",
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
  const file = "dist" + url;
  digest.update(url + "\n");
  digest.update(readFileSync(file));
}
// Content alone does not identify what a client caches: the shell is stored
// with its response headers, and the relay computes the CSP among them from
// settings that change without a rebuild. So the serving relay appends a digest
// of that configuration, and turning a setting on reaches clients as an
// ordinary update instead of stranding them on a CSP that predates it. A static
// host leaves the placeholder standing, which is right there — nothing rewrites
// headers per deployment.
const cacheName = "partage-" + digest.digest("hex").slice(0, 16) + "-__CONFIG_DIGEST__";

const generated = generateSW({
  cacheName,
  precacheUrls,
  navigationFallback: "/app.html",
  networkFirstPrefixes: ["/en", "/fr"],
  networkOnlyPrefixes: ["/api/", "/admin"],
  transformNotification: readFileSync(
    "public/sw-transform-notification.js",
    "utf-8",
  ),
});

const navigationFallbackMarker =
  "  // Navigation requests: serve the cached app shell (Elm handles routing)";
if (!generated.includes(navigationFallbackMarker)) {
  throw new Error("elm-pwa service-worker navigation marker changed");
}

// The language-negotiating root is not an SPA route. Prefix routing cannot
// express that exact path without also swallowing every offline app route.
const rootNavigation = `  if (event.request.mode === "navigate" && pathname === "/") {
    event.respondWith(fetch(event.request));
    return;
  }

`;
writeFileSync(
  "dist/sw.js",
  generated.replace(
    navigationFallbackMarker,
    rootNavigation + navigationFallbackMarker,
  ),
);
