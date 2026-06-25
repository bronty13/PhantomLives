// Redaction tokenizer + type metadata — pure ES module shared by the browser,
// the CLI, and tests. build.py inlines this into the browser (stripping the
// `export` keywords); Node imports it directly.
//
// TYPE_META: internal detector type -> { label (redaction token), color (UI) }.
// TYPE_ORDER drives the type panel, legend, and summary grouping order.

export const TYPE_META = {
  IPAddress:      { label: "IP",       color: "#2D6A4F" },
  Email:          { label: "EMAIL",    color: "#0096C7" },
  SSN:            { label: "SSN",      color: "#CF2E2E" },
  VIN:            { label: "VIN",      color: "#7B5EA7" },
  Routing:        { label: "ROUTING",  color: "#B8860B" },
  Phone:          { label: "PHONE",    color: "#FF6900" },
  DOB:            { label: "DOB",      color: "#00A878" },
  Passport:       { label: "PASSPORT", color: "#6A4C93" },
  DriversLicense: { label: "DL",       color: "#9C27B0" },
  CreditCard:     { label: "CARD",     color: "#C2185B" },
  Account:        { label: "ACCOUNT",  color: "#E0A800" },
  Name:           { label: "NAME",     color: "#00B4D8" },
  Address1:       { label: "ADDRESS",  color: "#E63946" },
  Address2:       { label: "ADDRESS2", color: "#F4845F" },
  City:           { label: "CITY",     color: "#00B050" },
  State:          { label: "STATE",    color: "#0077B6" },
  Zip:            { label: "ZIP",      color: "#5E60CE" }
};

export const TYPE_ORDER = Object.keys(TYPE_META);

export function normVal(v) { return v.toLowerCase().replace(/\s+/g, " ").trim(); }

export function makeCounters() { return {}; }

// Token for a single match under a redaction style.
//   labeled  -> [NAME]
//   numbered -> [NAME_1] (same normalized value reuses its token; counters carries state)
//   mask     -> ████ (length-clamped block run)
export function tokenFor(m, style, counters) {
  const label = (TYPE_META[m.type] || { label: m.type.toUpperCase() }).label;
  if (style === "mask") {
    const len = Math.max(4, Math.min(16, m.value.replace(/\s/g, "").length));
    return "█".repeat(len);
  }
  if (style === "numbered") {
    const bucket = counters[m.type] || (counters[m.type] = { map: new Map(), n: 0 });
    const key = normVal(m.value);
    let idx = bucket.map.get(key);
    if (idx === undefined) { idx = ++bucket.n; bucket.map.set(key, idx); }
    return "[" + label + "_" + idx + "]";
  }
  return "[" + label + "]";
}

// Build the full redacted string. matches must be sorted by start (detect() is).
export function redact(text, matches, style) {
  const counters = makeCounters();
  let out = "", cursor = 0;
  for (const m of matches) {
    out += text.slice(cursor, m.start) + tokenFor(m, style, counters);
    cursor = m.end;
  }
  return out + text.slice(cursor);
}
