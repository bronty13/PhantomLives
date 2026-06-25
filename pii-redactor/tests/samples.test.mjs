// Sample-data tests: run the real engine over the committed sample files to
// confirm they exercise the detectors (including the keyword-gated ones).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeEngine } from "../src/engine.js";
import { loadData } from "../src/data-node.mjs";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const { detect } = makeEngine(loadData(join(ROOT, "data")));

const SAMPLES = ["loan-application.txt", "customers.csv", "contacts.json", "server.log", "notes.md", "patients.txt"];

function typesIn(text) {
  const s = new Set();
  for (const m of detect(text)) s.add(m.type);
  return s;
}

for (const f of SAMPLES) {
  test(`${f} exists and yields detections`, () => {
    const p = join(ROOT, "samples", f);
    assert.ok(existsSync(p), `${f} missing`);
    const found = detect(readFileSync(p, "utf8"));
    assert.ok(found.length > 0, `${f} produced no detections`);
  });
}

test("across all samples, the keyword-gated types all fire somewhere", () => {
  const all = new Set();
  for (const f of SAMPLES) {
    const p = join(ROOT, "samples", f);
    if (existsSync(p)) for (const t of typesIn(readFileSync(p, "utf8"))) all.add(t);
  }
  for (const gated of ["DOB", "Routing", "Passport", "DriversLicense", "IPAddress", "CreditCard"]) {
    assert.ok(all.has(gated), `no sample triggers ${gated}`);
  }
});
