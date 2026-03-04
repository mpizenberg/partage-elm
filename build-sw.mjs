import { generateSW } from "./vendor/elm-pwa/js/src/build.js";
import { writeFileSync } from "node:fs";

writeFileSync(
  "dist/sw.js",
  generateSW({
    cacheName: "partage-v1",
    precacheUrls: [
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
    ],
    navigationFallback: "/",
    networkFirstPrefixes: ["/api/"],
    networkOnlyPrefixes: [],
  }),
);
