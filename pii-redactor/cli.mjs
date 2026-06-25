#!/usr/bin/env node
// PII Redactor — command-line interface.
//
// Reuses the SAME detection engine and redactor the browser app uses
// (src/engine.js, src/redact.js), so CLI and GUI agree exactly.
//
// Usage:
//   node cli.mjs [options] [file ...]
//   cat file | node cli.mjs [options]
//
// Options:
//   --style labeled|numbered|mask   Redaction style (default: labeled)
//   --types  A,B,C                  Only redact these types (comma list)
//   --exclude A,B,C                 Redact everything except these types
//   --json                          Output detections as JSON (no redaction)
//   --stats                         Print per-type counts to stderr
//   -o, --output FILE               Write redacted output to FILE (default: stdout)
//   -l, --list-types                List all detectable types and exit
//   -h, --help                      Show this help
//
// Input is plain text (and stdin). For PDF / Word .docx, use the app.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeEngine } from "./src/engine.js";
import { redact, TYPE_ORDER, TYPE_META } from "./src/redact.js";
import { loadData } from "./src/data-node.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function usage() {
  const text = readFileSync(fileURLToPath(import.meta.url), "utf8");
  const block = text.split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3));
  // print the header comment up to the first blank-after-usage
  process.stderr.write(block.slice(0, 26).join("\n") + "\n");
}

function parseArgs(argv) {
  const opts = { style: "labeled", types: null, exclude: null, json: false, stats: false, output: null, files: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--style") opts.style = argv[++i];
    else if (a === "--types") opts.types = argv[++i];
    else if (a === "--exclude") opts.exclude = argv[++i];
    else if (a === "--json") opts.json = true;
    else if (a === "--stats") opts.stats = true;
    else if (a === "-o" || a === "--output") opts.output = argv[++i];
    else if (a === "-l" || a === "--list-types") opts.listTypes = true;
    else if (a === "-h" || a === "--help") opts.help = true;
    else if (a.startsWith("-") && a !== "-") { process.stderr.write(`Unknown option: ${a}\n`); process.exit(2); }
    else opts.files.push(a);
  }
  return opts;
}

// Resolve a user-supplied type list (case-insensitive, by internal name or label)
// to a Set of canonical internal type names.
function resolveTypes(list) {
  const byLower = {};
  for (const t of TYPE_ORDER) { byLower[t.toLowerCase()] = t; byLower[TYPE_META[t].label.toLowerCase()] = t; }
  const out = new Set();
  for (const raw of list.split(",")) {
    const key = raw.trim().toLowerCase();
    if (!key) continue;
    if (byLower[key]) out.add(byLower[key]);
    else { process.stderr.write(`Unknown type: ${raw.trim()} (use --list-types)\n`); process.exit(2); }
  }
  return out;
}

function readStdin() {
  try { return readFileSync(0, "utf8"); } catch { return ""; }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) { usage(); return 0; }
  if (opts.listTypes) {
    for (const t of TYPE_ORDER) process.stdout.write(`${t.padEnd(16)} [${TYPE_META[t].label}]\n`);
    return 0;
  }

  const data = loadData(join(HERE, "data"));
  const engine = makeEngine(data);

  let enabled = new Set(TYPE_ORDER);
  if (opts.types) enabled = resolveTypes(opts.types);
  if (opts.exclude) { const ex = resolveTypes(opts.exclude); enabled = new Set(TYPE_ORDER.filter((t) => !ex.has(t))); }

  // Gather input: files, or stdin if none.
  const inputs = [];
  if (opts.files.length) {
    for (const f of opts.files) {
      if (/\.(pdf|docx|doc)$/i.test(f)) { process.stderr.write(`Skipping ${f}: binary formats (PDF/Word) are GUI-only.\n`); continue; }
      inputs.push({ name: f, text: readFileSync(f, "utf8") });
    }
  } else {
    inputs.push({ name: "<stdin>", text: readStdin() });
  }
  if (!inputs.length) { process.stderr.write("No readable input.\n"); return 1; }

  const pieces = [];
  const totals = {};
  for (const inp of inputs) {
    const all = engine.detect(inp.text);
    const matches = all.filter((m) => enabled.has(m.type));
    for (const m of matches) totals[m.type] = (totals[m.type] || 0) + 1;

    if (opts.json) {
      pieces.push(JSON.stringify({ file: inp.name, count: matches.length, matches }, null, 2));
    } else {
      pieces.push(redact(inp.text, matches, opts.style));
    }
  }

  const output = pieces.join(opts.json ? "\n" : "\n");
  if (opts.output) writeFileSync(opts.output, output);
  else process.stdout.write(output + (output.endsWith("\n") ? "" : "\n"));

  if (opts.stats) {
    const lines = TYPE_ORDER.filter((t) => totals[t]).map((t) => `  ${t.padEnd(16)} ${totals[t]}`);
    const grand = Object.values(totals).reduce((a, b) => a + b, 0);
    process.stderr.write(`Detected ${grand} item(s) across ${inputs.length} input(s):\n${lines.join("\n")}\n`);
  }
  return 0;
}

main().then((code) => process.exit(code || 0)).catch((err) => { process.stderr.write(String(err && err.stack || err) + "\n"); process.exit(1); });
