import { parseCsvToObjects } from './csv';

/**
 * Generic sales-report importer.
 *
 * Each site (Clips4Sale, IWantClips, OnlyFans, …) exports a different
 * CSV format, but they all boil down to "date + amount" rows. Rather
 * than hard-code N parsers, we auto-detect the date and amount columns
 * by header name, allow override, then aggregate to per-month totals
 * which the income_site table consumes via `upsertSiteIncome`.
 */

export interface SalesRow {
  date: Date;
  amount: number;
  raw: Record<string, string>;
}

export interface MonthBucket {
  year: number;
  month: number;          // 1-12
  amount: number;
  rowCount: number;
}

export interface DetectedColumns {
  dateColumn: string | null;
  amountColumn: string | null;
}

export interface ParseResult {
  header: string[];
  detected: DetectedColumns;
  rows: SalesRow[];
  unparseable: { lineNo: number; reason: string; data: Record<string, string> }[];
  byMonth: MonthBucket[];
}

// Headers we recognize, in priority order.
const DATE_KEYWORDS = [
  'date',
  'day',
  'transaction date',
  'period',
  'sale date',
  'earned on',
  'earning date',
  'created',
  'created at',
  'datetime',
  'timestamp',
];

const AMOUNT_KEYWORDS = [
  'payout',
  'net',
  'net amount',
  'net payout',
  'creator payout',
  'amount',
  'total',
  'earned',
  'earnings',
  'gross',
  'price',
  'usd',
  'subtotal',
  'payment',
];

function normalize(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, ' ');
}

export function detectColumns(header: string[]): DetectedColumns {
  const lower = header.map(normalize);
  function findByKeywords(keywords: string[]): string | null {
    for (const k of keywords) {
      const idx = lower.findIndex((h) => h === k || h.includes(k));
      if (idx !== -1) return header[idx];
    }
    return null;
  }
  return {
    dateColumn: findByKeywords(DATE_KEYWORDS),
    amountColumn: findByKeywords(AMOUNT_KEYWORDS),
  };
}

const MONEY_REGEX = /[-+]?\$?\s*([\d,]+(?:\.\d+)?)/;

export function parseMoneyLoose(s: string): number | null {
  if (!s) return null;
  const trimmed = s.trim();
  if (trimmed === '' || trimmed === '-' || trimmed.toLowerCase() === 'n/a') return null;
  const m = MONEY_REGEX.exec(trimmed);
  if (!m) return null;
  const cleaned = m[1].replace(/,/g, '');
  const n = parseFloat(cleaned);
  if (!Number.isFinite(n)) return null;
  // Preserve negative sign if present anywhere in the source string.
  return trimmed.includes('-') ? -Math.abs(n) : n;
}

/**
 * Try to parse a date from one of several common formats. Returns a
 * local-midnight Date or null.
 */
export function parseDateLoose(s: string): Date | null {
  if (!s) return null;
  const trimmed = s.trim();
  if (trimmed === '') return null;

  // ISO YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(trimmed);
  if (m) {
    const y = +m[1]; const mm = +m[2]; const d = +m[3];
    if (isValidYmd(y, mm, d)) return new Date(y, mm - 1, d);
  }
  // YYYY/MM/DD
  m = /^(\d{4})\/(\d{1,2})\/(\d{1,2})/.exec(trimmed);
  if (m) {
    const y = +m[1]; const mm = +m[2]; const d = +m[3];
    if (isValidYmd(y, mm, d)) return new Date(y, mm - 1, d);
  }
  // MM/DD/YYYY (US) or DD/MM/YYYY (EU). If first piece > 12, assume EU.
  m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(trimmed);
  if (m) {
    const a = +m[1]; const b = +m[2]; const y = +m[3];
    if (a > 12 && b <= 12 && isValidYmd(y, b, a)) return new Date(y, b - 1, a);     // EU: a=day, b=month
    if (a <= 12 && isValidYmd(y, a, b)) return new Date(y, a - 1, b);                // US: a=month, b=day
  }
  // Mon DD, YYYY (e.g. "Jan 5, 2026")
  const monthNames = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  m = /^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})/.exec(trimmed);
  if (m) {
    const monIdx = monthNames.indexOf(m[1].slice(0, 3).toLowerCase());
    const d = +m[2]; const y = +m[3];
    if (monIdx !== -1 && isValidYmd(y, monIdx + 1, d)) return new Date(y, monIdx, d);
  }
  // Last-resort: Date constructor (will accept many freeform strings, but we
  // discard if it produced an "Invalid Date").
  const fallback = new Date(trimmed);
  if (!Number.isNaN(fallback.getTime())) return fallback;
  return null;
}

function isValidYmd(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  if (y < 1990 || y > 2100) return false;
  const test = new Date(y, m - 1, d);
  return test.getFullYear() === y && test.getMonth() === m - 1 && test.getDate() === d;
}

export interface ParseOptions {
  dateColumn?: string;
  amountColumn?: string;
}

export function parseSalesReport(text: string, opts: ParseOptions = {}): ParseResult {
  const { header, rows } = parseCsvToObjects(text);
  const detected = detectColumns(header);
  const dateCol = opts.dateColumn ?? detected.dateColumn;
  const amountCol = opts.amountColumn ?? detected.amountColumn;

  const parsed: SalesRow[] = [];
  const unparseable: ParseResult['unparseable'] = [];

  rows.forEach((row, idx) => {
    if (!dateCol || !amountCol) {
      unparseable.push({ lineNo: idx + 2, reason: 'no date/amount column detected', data: row });
      return;
    }
    const dateRaw = row[dateCol];
    const amountRaw = row[amountCol];
    const date = parseDateLoose(dateRaw ?? '');
    const amount = parseMoneyLoose(amountRaw ?? '');
    if (date === null) {
      unparseable.push({ lineNo: idx + 2, reason: `unparseable date "${dateRaw}"`, data: row });
      return;
    }
    if (amount === null) {
      unparseable.push({ lineNo: idx + 2, reason: `unparseable amount "${amountRaw}"`, data: row });
      return;
    }
    parsed.push({ date, amount, raw: row });
  });

  // Aggregate by (year, month).
  const buckets = new Map<string, MonthBucket>();
  for (const r of parsed) {
    const y = r.date.getFullYear();
    const m = r.date.getMonth() + 1;
    const key = `${y}-${m.toString().padStart(2, '0')}`;
    const b = buckets.get(key) ?? { year: y, month: m, amount: 0, rowCount: 0 };
    b.amount += r.amount;
    b.rowCount += 1;
    buckets.set(key, b);
  }
  const byMonth = [...buckets.values()].sort((a, b) => {
    if (a.year !== b.year) return a.year - b.year;
    return a.month - b.month;
  });

  return { header, detected, rows: parsed, unparseable, byMonth };
}
