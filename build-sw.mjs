import { generateSW } from "./vendor/elm-pwa/js/src/build.js";
import { readFileSync, writeFileSync } from "node:fs";

writeFileSync(
  "dist/sw.js",
  generateSW({
    cacheName: "partage-v7",
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
    networkFirstPrefixes: [],
    networkOnlyPrefixes: ["/api/"],
    transformNotification: readFileSync(
      "public/sw-transform-notification.js",
      "utf-8",
    ),
  }),
);
