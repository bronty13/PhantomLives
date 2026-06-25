// CLI tests — spawn the real cli.mjs so the end-to-end path is exercised.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const CLI = join(ROOT, "cli.mjs");
const INPUT = "SSN: 234-45-3455 for John Smith, email john@example.com, born on Date of birth: 04/12/1986";

function run(args, input) {
  return execFileSync("node", [CLI, ...args], { input: input ?? "", encoding: "utf8" });
}

test("default labeled redaction over stdin", () => {
  const out = run([], INPUT);
  assert.match(out, /\[SSN\]/);
  assert.match(out, /\[EMAIL\]/);
  assert.ok(!out.includes("234-45-3455"), "SSN leaked");
  assert.ok(!out.includes("john@example.com"), "email leaked");
});

test("--types restricts what is redacted", () => {
  const out = run(["--types", "SSN"], INPUT);
  assert.match(out, /\[SSN\]/);
  assert.ok(out.includes("john@example.com"), "email should remain when only SSN selected");
});

test("--style numbered", () => {
  // Names at line start (no preceding word token) detect cleanly; the same
  // value reuses its number, a different value gets the next.
  const out = run(["--style", "numbered"], "John Smith\nJohn Smith\nMary Jones");
  assert.match(out, /\[NAME_1\].*\[NAME_1\].*\[NAME_2\]/s);
});

test("--json emits structured detections", () => {
  const out = run(["--json"], INPUT);
  const parsed = JSON.parse(out);
  assert.ok(Array.isArray(parsed.matches));
  assert.ok(parsed.matches.some((m) => m.type === "SSN"));
  assert.equal(typeof parsed.count, "number");
});

test("--list-types lists every type", () => {
  const out = run(["--list-types"], "");
  for (const t of ["Name", "Email", "SSN", "Routing", "Passport", "DriversLicense", "IPAddress"]) {
    assert.match(out, new RegExp("\\b" + t + "\\b"));
  }
});

test("--exclude removes a type", () => {
  const out = run(["--exclude", "Email"], INPUT);
  assert.ok(out.includes("john@example.com"), "excluded email should remain");
  assert.match(out, /\[SSN\]/);
});
