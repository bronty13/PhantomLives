// Headless test of the detection engine as it ships in dist/pii-redactor.html.
// Extracts the inlined worker source (engine + reference data), runs it in a
// vm sandbox with self/window shims, and asserts detect() on the sample text.
// Run: node tests/engine.test.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const html = readFileSync(join(ROOT, "dist", "pii-redactor.html"), "utf8");

// --- extract the detection worker source (engine + inlined data) ---
const m = html.match(/<script type="text\/js-worker" id="detectWorkerSrc">([\s\S]*?)<\/script>/);
assert.ok(m, "detectWorkerSrc script not found in built file");
const workerSrc = m[1].replace(/<\\\/script/g, "</script"); // undo build-time escaping

// --- run it in a sandbox; capture detect() and the ready stats ---
let readyStats = null;
const sandbox = {};
sandbox.self = {
  postMessage(msg) { if (msg && msg.type === "ready") readyStats = msg.stats; },
  set onmessage(_) {}, get onmessage() { return null; },
};
sandbox.Set = Set; sandbox.Map = Map; sandbox.Object = Object;
sandbox.RegExp = RegExp; sandbox.Math = Math; sandbox.parseInt = parseInt;
vm.createContext(sandbox);
vm.runInContext(workerSrc, sandbox, { filename: "detectWorker.js" });

const detect = sandbox.detect;
assert.equal(typeof detect, "function", "detect() not exported from worker scope");

// --- 1. reference data inlined and parsed ---
assert.ok(readyStats, "worker never posted ready stats");
assert.ok(readyStats.first > 4000,  `first names too few: ${readyStats.first}`);
assert.ok(readyStats.last > 150000, `surnames too few: ${readyStats.last}`);
assert.ok(readyStats.places > 20000, `places too few: ${readyStats.places}`);
console.log(`✓ data inlined: ${readyStats.first} first, ${readyStats.last} last, ${readyStats.places} places`);

// --- 2. sample coverage: every expected type is detected ---
const sample = `Customer: John Q. Smith
Email: john.smith@example.com
123 Main Street
Suite 401
Milwaukee, WI 53202
Phone: (716) 234-2242
Loan account: 53563453-3
SSN: 234-45-3455
Date of birth: 04/12/1986
Bank routing (ABA): 021000021
VIN 1HGBH41JXMN109186
Visa 4111 1111 1111 1111
client 192.168.1.42 talking to 10.0.0.7
Driver's license no D1234567
Passport number X1234567
previously resided in Chicago, IL 60601`;

const found = detect(sample);
const byType = {};
for (const f of found) (byType[f.type] ||= []).push(f.value);

const expected = ["Name", "Email", "Address1", "Address2", "City", "State", "Zip",
                  "Phone", "Account", "SSN", "DOB", "Routing", "VIN", "CreditCard",
                  "IPAddress", "DriversLicense", "Passport"];
const missing = expected.filter((t) => !byType[t]);
assert.deepEqual(missing, [], `missing detections: ${missing.join(", ")}`);
console.log(`✓ all ${expected.length} expected PII types detected`);

// --- 3. specific-value correctness ---
assert.ok(byType.Routing.includes("021000021"), "valid ABA routing not caught");
assert.ok(byType.CreditCard.includes("4111 1111 1111 1111"), "Visa not caught");
assert.ok(byType.IPAddress.includes("192.168.1.42"), "IPv4 not caught");
assert.ok(byType.DriversLicense.includes("D1234567"), "DL token not caught");
assert.ok(byType.Passport.includes("X1234567"), "passport token not caught");
console.log("✓ value-level checks pass");

// --- 4. keyword gating: a bare date / 9-digit / IP-less number is NOT over-flagged ---
const noKw = detect("The invoice is due 12/25/2024 and ref number 021000021 applies.");
const noKwTypes = new Set(noKw.map((f) => f.type));
assert.ok(!noKwTypes.has("DOB"), "DOB flagged without a birth keyword (false positive)");
assert.ok(!noKwTypes.has("Routing"), "Routing flagged without an ABA keyword (false positive)");
console.log("✓ keyword gating suppresses ungated dates & 9-digit numbers");

// --- 5. ABA checksum rejects an invalid 9-digit number even with the keyword ---
const badAba = detect("Bank routing number 123456789 is on file.");
assert.ok(!badAba.some((f) => f.type === "Routing"), "invalid ABA checksum was accepted");
console.log("✓ ABA checksum rejects invalid routing numbers");

console.log("\nALL TESTS PASSED");
