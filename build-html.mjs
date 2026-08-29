import { readFileSync, writeFileSync } from "node:fs";

for (const filename of ["app.html", "robots.txt", "sitemap.xml"]) {
  writeFileSync(`dist/${filename}`, readFileSync(`public/${filename}`, "utf8"));
}
