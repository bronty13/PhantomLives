/**
 * Minimal RFC 4180 CSV parser. Handles:
 *  - quoted fields (with embedded `,` and newlines)
 *  - escaped quotes (`""` inside quoted fields)
 *  - CRLF and LF line endings
 *  - leading UTF-8 BOM
 *
 * We do not depend on papaparse to keep the bundle small; this is ~60 lines.
 */
export function parseCsv(text: string): string[][] {
  let s = text;
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1); // strip BOM

  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;
  let i = 0;
  const n = s.length;

  while (i < n) {
    const c = s[i];

    if (inQuotes) {
      if (c === '"') {
        if (s[i + 1] === '"') { cell += '"'; i += 2; continue; }
        inQuotes = false;
        i += 1;
      } else {
        cell += c;
        i += 1;
      }
      continue;
    }

    if (c === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (c === ',') {
      row.push(cell);
      cell = '';
      i += 1;
      continue;
    }
    if (c === '\r') {
      // swallow optional LF
      if (s[i + 1] === '\n') i += 1;
      row.push(cell);
      cell = '';
      rows.push(row);
      row = [];
      i += 1;
      continue;
    }
    if (c === '\n') {
      row.push(cell);
      cell = '';
      rows.push(row);
      row = [];
      i += 1;
      continue;
    }
    cell += c;
    i += 1;
  }

  // Last cell
  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }

  // Drop trailing empty row from final newline.
  if (rows.length > 0) {
    const last = rows[rows.length - 1];
    if (last.length === 1 && last[0] === '') rows.pop();
  }

  return rows;
}

/** Convenience: returns `{ header, rows }` where rows are objects keyed by header. */
export function parseCsvToObjects(text: string): { header: string[]; rows: Record<string, string>[] } {
  const matrix = parseCsv(text);
  if (matrix.length === 0) return { header: [], rows: [] };
  const header = matrix[0].map((h) => h.trim());
  const rows = matrix.slice(1).map((cells) => {
    const obj: Record<string, string> = {};
    header.forEach((h, idx) => {
      obj[h] = cells[idx] ?? '';
    });
    return obj;
  });
  return { header, rows };
}
