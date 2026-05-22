/**
 * Pipe-delimited CSV parser for the Clips4Sale export format.
 *
 * C4S uses `|` as the field separator and double-quotes every field. The
 * trick is the `Clip Description` column: it contains raw user prose with
 * literal newlines, paragraph breaks, and the occasional `|`. A
 * comma-only parser (or a naive line splitter) tears those rows apart.
 *
 * Mirrors `lib/csv.ts` but with `|` swapped for `,`. Same RFC 4180
 * machinery: quoted fields containing embedded `|`, `\n`, `\r\n` work;
 * `""` inside a quoted field is an escaped quote; the leading UTF-8 BOM
 * is stripped; CRLF and LF row terminators both close a record.
 */
export function parsePipeCsv(text: string): string[][] {
  let s = text;
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);

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
    if (c === '|') {
      row.push(cell);
      cell = '';
      i += 1;
      continue;
    }
    if (c === '\r') {
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

  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }

  if (rows.length > 0) {
    const last = rows[rows.length - 1];
    if (last.length === 1 && last[0] === '') rows.pop();
  }

  return rows;
}

/** `{ header, rows }` where rows are objects keyed by trimmed header. */
export function parsePipeCsvToObjects(text: string): { header: string[]; rows: Record<string, string>[] } {
  const matrix = parsePipeCsv(text);
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
