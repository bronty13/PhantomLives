// Build-integration test: build the single file and assert everything inlined.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const DIST = join(ROOT, "dist", "pii-redactor.html");
let html = "";

before(() => {
  execFileSync("python3", ["build.py"], { cwd: ROOT, encoding: "utf8" });
  html = readFileSync(DIST, "utf8");
});

test("no INLINE markers remain", () => {
  assert.ok(!html.includes("INLINE:"), "an INLINE marker was left unconsumed");
});

test("engine, redactor, markdown, data, manual, vendor libs all inlined", () => {
  assert.match(html, /function makeEngine\(/, "engine not inlined");
  assert.match(html, /TYPE_META\s*=/, "redactor not inlined");
  assert.match(html, /function renderMarkdown\(/, "markdown not inlined");
  assert.match(html, /PII_FIRST_NAMES/, "reference data not inlined");
  assert.match(html, /PII Redactor — User Manual/, "user manual not inlined");
  assert.match(html, /pdfjsLib/, "pdf.js not inlined");
  assert.match(html, /mammoth/, "mammoth not inlined");
});

test("the inlined modules have their export keyword stripped", () => {
  // After stripping, no bare `export ` should survive in the single file.
  assert.ok(!/\bexport\s+(function|const|default)\b/.test(html), "an export keyword survived inlining");
});

test("built file is a reasonable single-file size (3-6 MB)", () => {
  const mb = statSync(DIST).size / (1024 * 1024);
  assert.ok(mb > 3 && mb < 6, `unexpected size ${mb.toFixed(2)} MB`);
});

test("CSP blocks outbound connections", () => {
  assert.match(html, /connect-src 'none'/);
});
