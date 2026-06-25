// Detection engine tests — imports the shared module directly.
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeEngine } from "../src/engine.js";
import { loadData } from "../src/data-node.mjs";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const data = loadData(join(ROOT, "data"));
const { detect } = makeEngine(data);

const SAMPLE = `Customer: John Q. Smith
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

function group(matches) {
  const by = {};
  for (const m of matches) (by[m.type] ||= []).push(m.value);
  return by;
}

test("reference data loaded", () => {
  assert.ok(data.firstNames.size > 4000);
  assert.ok(data.lastNames.size > 150000);
  assert.ok(Object.keys(data.places).length > 20000);
});

test("all expected PII types detected in the sample", () => {
  const by = group(detect(SAMPLE));
  const expected = ["Name", "Email", "Address1", "Address2", "City", "State", "Zip",
                    "Phone", "Account", "SSN", "DOB", "Routing", "VIN", "CreditCard",
                    "IPAddress", "DriversLicense", "Passport"];
  const missing = expected.filter((t) => !by[t]);
  assert.deepEqual(missing, [], `missing: ${missing.join(", ")}`);
});

test("value-level correctness", () => {
  const by = group(detect(SAMPLE));
  assert.ok(by.Routing.includes("021000021"));
  assert.ok(by.CreditCard.includes("4111 1111 1111 1111"));
  assert.ok(by.IPAddress.includes("192.168.1.42"));
  assert.ok(by.DriversLicense.includes("D1234567"));
  assert.ok(by.Passport.includes("X1234567"));
  assert.ok(by.Zip.includes("53202"), "5-digit ZIP must be typed Zip, not Account");
});

test("keyword gating suppresses ungated dates and 9-digit numbers", () => {
  const by = group(detect("Invoice due 12/25/2024, ref number 021000021 applies."));
  assert.ok(!by.DOB, "DOB flagged without a birth keyword");
  assert.ok(!by.Routing, "Routing flagged without an ABA keyword");
});

test("ABA checksum rejects an invalid routing number even with the keyword", () => {
  const by = group(detect("Bank routing number 123456789 is on file."));
  assert.ok(!by.Routing, "invalid ABA checksum accepted");
});

test("Luhn + brand gating rejects a non-card 16-digit run", () => {
  const by = group(detect("Reference 1234567812345678 on the account."));
  assert.ok(!by.CreditCard, "non-Luhn 16-digit run accepted as a card");
});

test("empty / non-string input is safe", () => {
  assert.deepEqual(detect(""), []);
  assert.deepEqual(detect(undefined), []);
});
