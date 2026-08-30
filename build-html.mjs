import { readFileSync, writeFileSync } from "node:fs";

for (const filename of ["app.html", "robots.txt"]) {
  writeFileSync(`dist/${filename}`, readFileSync(`public/${filename}`, "utf8"));
}
