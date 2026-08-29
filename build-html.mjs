import { readFileSync, writeFileSync } from "node:fs";

// Canonical, Open Graph, and crawler-discovery URLs identify the deployed
// instance. A build for a static host bakes them in via CANONICAL_ORIGIN;
// without it the placeholder ships and the relay substitutes the origin it
// actually serves on, per request. A trailing slash is dropped so each
// template's own "/" wins.
const origin = (process.env.CANONICAL_ORIGIN || "").replace(/\/$/, "");

for (const filename of ["index.html", "robots.txt", "sitemap.xml"]) {
  const template = readFileSync(`public/${filename}`, "utf8");
  writeFileSync(
    `dist/${filename}`,
    origin === "" ? template : template.replaceAll("__CANONICAL_ORIGIN__", origin),
  );
}
