import { readFileSync, writeFileSync } from "node:fs";

// Canonical/Open Graph URLs identify the deployed instance. A build for a
// static host bakes them in via CANONICAL_ORIGIN; without it the placeholder
// ships and the relay substitutes the origin it actually serves on, per
// request. A trailing slash is dropped so the template's own "/" wins.
const origin = (process.env.CANONICAL_ORIGIN || "").replace(/\/$/, "");

const template = readFileSync("public/index.html", "utf8");
writeFileSync(
  "dist/index.html",
  origin === "" ? template : template.replaceAll("__CANONICAL_ORIGIN__", origin),
);
