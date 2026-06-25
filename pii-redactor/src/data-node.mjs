// Node-only loader for the reference data. The data files assign to `window.*`
// (so they double as browser <script>s); here we run them in a vm context with
// a `window` shim and pull the globals back out.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import vm from "node:vm";

export function loadData(dataDir) {
  const ctx = { window: {}, Set };
  vm.createContext(ctx);
  for (const f of ["first-names.js", "last-names.js", "places.js"]) {
    vm.runInContext(readFileSync(join(dataDir, f), "utf8"), ctx, { filename: f });
  }
  return {
    firstNames: ctx.window.PII_FIRST_NAMES || new Set(),
    lastNames: ctx.window.PII_LAST_NAMES || new Set(),
    places: ctx.window.PII_PLACES || {},
  };
}
