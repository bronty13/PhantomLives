// Redactor tests — token styles and numbered-pseudonym consistency.
import { test } from "node:test";
import assert from "node:assert/strict";
import { redact, tokenFor, makeCounters, TYPE_META, TYPE_ORDER } from "../src/redact.js";

const text = "John and JOHN and Mary at a@b.com end";
//            0123456789...   indices used below
const matches = [
  { start: 0,  end: 4,  type: "Name",  value: "John" },
  { start: 9,  end: 13, type: "Name",  value: "JOHN" },   // same person, different case
  { start: 18, end: 22, type: "Name",  value: "Mary" },
  { start: 26, end: 33, type: "Email", value: "a@b.com" },
];

test("labeled style", () => {
  assert.equal(redact(text, matches, "labeled"), "[NAME] and [NAME] and [NAME] at [EMAIL] end");
});

test("numbered style reuses a token for the same normalized value", () => {
  const out = redact(text, matches, "numbered");
  // John and JOHN normalize the same -> both NAME_1; Mary -> NAME_2
  assert.equal(out, "[NAME_1] and [NAME_1] and [NAME_2] at [EMAIL_1] end");
});

test("mask style hides the type and clamps length", () => {
  const out = redact("x", [{ start: 0, end: 1, type: "Name", value: "Christopher" }], "mask");
  assert.match(out, /^█+$/);
  assert.ok(out.length >= 4 && out.length <= 16);
});

test("every detector type has redaction metadata", () => {
  for (const t of TYPE_ORDER) {
    assert.ok(TYPE_META[t].label, `${t} missing label`);
    assert.ok(/^#[0-9A-Fa-f]{6}$/.test(TYPE_META[t].color), `${t} bad color`);
  }
});

test("counters carry numbering state across tokenFor calls", () => {
  const c = makeCounters();
  const a = tokenFor({ type: "SSN", value: "111-11-1111" }, "numbered", c);
  const b = tokenFor({ type: "SSN", value: "222-22-2222" }, "numbered", c);
  const again = tokenFor({ type: "SSN", value: "111-11-1111" }, "numbered", c);
  assert.equal(a, "[SSN_1]");
  assert.equal(b, "[SSN_2]");
  assert.equal(again, "[SSN_1]");
});
