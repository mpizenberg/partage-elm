import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const entries = JSON.parse(readFileSync("changelog.json", "utf8"));

test("dates are unique, so a seen-marker names exactly one entry", () => {
  const dates = entries.map((entry) => entry.date);
  assert.equal(new Set(dates).size, dates.length);
  for (const date of dates) {
    assert.match(date, /^\d{4}-\d{2}-\d{2}$/);
  }
});

test("entries are ordered newest first", () => {
  const dates = entries.map((entry) => entry.date);
  assert.deepEqual(dates, [...dates].sort().reverse());
});

test("every entry is complete in both languages", () => {
  for (const entry of entries) {
    for (const language of ["en", "fr"]) {
      assert.ok(entry[language]?.title, `${entry.date} ${language} title`);
      assert.ok(entry[language]?.body, `${entry.date} ${language} body`);
    }
  }
});
