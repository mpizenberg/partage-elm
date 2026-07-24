import { readFileSync, writeFileSync } from "node:fs";

// Canonical/Open Graph URLs identify the deployed instance. They default to the
// project site; a self-host build points them at its own domain via
// CANONICAL_ORIGIN. A trailing slash is dropped so the template's own "/" wins.
const DEFAULT_ORIGIN = "https://partage.dokploy.zidev.ovh";
const origin = (process.env.CANONICAL_ORIGIN || DEFAULT_ORIGIN).replace(/\/$/, "");

const html = readFileSync("public/index.html", "utf8").replaceAll(
  "__CANONICAL_ORIGIN__",
  origin,
);

writeFileSync("dist/index.html", html);
