import { db } from './db';
import type { Cadence } from '../lib/cadence';
import { isoDate, nextOccurrencesAfter, parseIso } from '../lib/cadence';

export interface Expense {
  id: number;
  actualDate: string;
  effectiveDate: string;
  description: string;
  note: string;
  attachmentPath: string | null;
  amount: number;
  personaCode: string | null;
  excluded: boolean;
  exclusionAmount: number | null;
  recurringId: number | null;
  createdAt: string;
  updatedAt: string;
}

interface ExpenseRow {
  id: number;
  actual_date: string;
  effective_date: string;
  description: string;
  note: string;
  attachment_path: string | null;
  amount: number;
  persona_code: string | null;
  excluded: number;
  exclusion_amount: number | null;
  recurring_id: number | null;
  created_at: string;
  updated_at: string;
}

function rowToExpense(r: ExpenseRow): Expense {
  return {
    id: r.id,
    actualDate: r.actual_date,
    effectiveDate: r.effective_date,
    description: r.description,
    note: r.note,
    attachmentPath: r.attachment_path,
    amount: r.amount,
    personaCode: r.persona_code,
    excluded: r.excluded !== 0,
    exclusionAmount: r.exclusion_amount,
    recurringId: r.recurring_id,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export interface ExpenseFilter {
  year?: number;
  month?: number;
  personaCode?: string;
  includeExcluded?: boolean;
}

export async function listExpenses(filter: ExpenseFilter = {}): Promise<Expense[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT id, actual_date, effective_date, description, note, attachment_path, amount, persona_code, excluded, exclusion_amount, recurring_id, created_at, updated_at FROM expenses WHERE 1=1`;
  if (filter.year) {
    params.push(`${filter.year}-`);
    sql += ` AND substr(effective_date, 1, 5) = $${params.length}`;
  }
  if (filter.year && filter.month) {
    const prefix = `${filter.year}-${filter.month.toString().padStart(2, '0')}-`;
    params.push(prefix);
    sql += ` AND substr(effective_date, 1, 8) = $${params.length}`;
  }
  if (filter.personaCode && filter.personaCode !== 'ALL') {
    params.push(filter.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  if (!filter.includeExcluded) {
    // Even with includeExcluded=false we still return all rows but the UI
    // / reports can treat `excluded` differently. Leaving this clause off
    // entirely keeps the data layer flexible.
  }
  sql += ` ORDER BY effective_date DESC, id DESC`;
  const rows = await conn.select<ExpenseRow[]>(sql, params);
  return rows.map(rowToExpense);
}

export async function createExpense(input: Omit<Expense, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO expenses (actual_date, effective_date, description, note, attachment_path, amount, persona_code, excluded, exclusion_amount, recurring_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
    [
      input.actualDate,
      input.effectiveDate,
      input.description,
      input.note,
      input.attachmentPath,
      input.amount,
      input.personaCode,
      input.excluded ? 1 : 0,
      input.exclusionAmount,
      input.recurringId,
    ],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updateExpense(e: Expense): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE expenses SET actual_date = $1, effective_date = $2, description = $3, note = $4, attachment_path = $5, amount = $6, persona_code = $7, excluded = $8, exclusion_amount = $9, recurring_id = $10, updated_at = datetime('now') WHERE id = $11`,
    [
      e.actualDate, e.effectiveDate, e.description, e.note, e.attachmentPath, e.amount,
      e.personaCode, e.excluded ? 1 : 0, e.exclusionAmount, e.recurringId, e.id,
    ],
  );
}

export async function deleteExpense(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM expenses WHERE id = $1', [id]);
}

// ---------- Recurring expenses --------------------------------------------

export interface RecurringExpense {
  id: number;
  description: string;
  amount: number;
  personaCode: string | null;
  cadence: Cadence;
  anchorDate: string;
  lastMaterial: string | null;
  note: string;
  active: boolean;
}

interface RecurringRow {
  id: number;
  description: string;
  amount: number;
  persona_code: string | null;
  cadence_json: string;
  anchor_date: string;
  last_material: string | null;
  note: string;
  active: number;
}

function rowToRecurring(r: RecurringRow): RecurringExpense {
  let cadence: Cadence;
  try { cadence = JSON.parse(r.cadence_json) as Cadence; } catch { cadence = { kind: 'monthly_dom', day: 1 }; }
  return {
    id: r.id,
    description: r.description,
    amount: r.amount,
    personaCode: r.persona_code,
    cadence,
    anchorDate: r.anchor_date,
    lastMaterial: r.last_material,
    note: r.note,
    active: r.active !== 0,
  };
}

export async function listRecurring(): Promise<RecurringExpense[]> {
  const conn = await db();
  const rows = await conn.select<RecurringRow[]>(
    'SELECT id, description, amount, persona_code, cadence_json, anchor_date, last_material, note, active FROM expenses_recurring ORDER BY active DESC, description',
  );
  return rows.map(rowToRecurring);
}

export async function createRecurring(input: Omit<RecurringExpense, 'id' | 'lastMaterial'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO expenses_recurring (description, amount, persona_code, cadence_json, anchor_date, note, active)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      input.description, input.amount, input.personaCode,
      JSON.stringify(input.cadence), input.anchorDate, input.note,
      input.active ? 1 : 0,
    ],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updateRecurring(r: RecurringExpense): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE expenses_recurring SET description = $1, amount = $2, persona_code = $3, cadence_json = $4, anchor_date = $5, note = $6, active = $7, updated_at = datetime('now') WHERE id = $8`,
    [
      r.description, r.amount, r.personaCode,
      JSON.stringify(r.cadence), r.anchorDate, r.note,
      r.active ? 1 : 0, r.id,
    ],
  );
}

export async function deleteRecurring(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM expenses_recurring WHERE id = $1', [id]);
}

/**
 * Walk every active recurring expense forward to today, INSERT OR
 * IGNORE into expenses. Idempotent via the unique index on
 * (recurring_id, effective_date).
 */
export async function materializeRecurringExpenses(): Promise<{ inserted: number }> {
  const conn = await db();
  const list = await listRecurring();
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const todayIso = isoDate(today);
  let inserted = 0;

  for (const r of list) {
    if (!r.active) continue;
    // Start from the day AFTER lastMaterial (or anchorDate if none).
    const fromIso = r.lastMaterial ?? r.anchorDate;
    const from = parseIso(fromIso);
    const candidates = nextOccurrencesAfter(r.cadence, from, 200, !r.lastMaterial);
    let latest: string | null = r.lastMaterial;
    for (const due of candidates) {
      if (due > todayIso) break;
      const result = await conn.execute(
        `INSERT OR IGNORE INTO expenses (actual_date, effective_date, description, note, amount, persona_code, recurring_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [due, due, r.description, r.note, r.amount, r.personaCode, r.id],
      );
      if (result.rowsAffected && result.rowsAffected > 0) inserted++;
      latest = due;
    }
    if (latest && latest !== r.lastMaterial) {
      await conn.execute(
        `UPDATE expenses_recurring SET last_material = $1 WHERE id = $2`,
        [latest, r.id],
      );
    }
  }
  return { inserted };
}

// ---------- Reporting helpers ---------------------------------------------

/** Net amount = full amount unless excluded (then 0) or partially excluded (then amount - exclusion_amount). */
export function netAmount(e: Expense): number {
  if (e.excluded) return 0;
  if (e.exclusionAmount && e.exclusionAmount > 0) {
    return Math.max(0, e.amount - e.exclusionAmount);
  }
  return e.amount;
}

export interface ExpenseTotals {
  net: number;
  gross: number;
  excludedTotal: number;
  count: number;
}

export async function expenseTotalsForPeriod(opts: { year: number; month?: number; dayCap?: number; personaCode?: string }): Promise<ExpenseTotals> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT amount, excluded, exclusion_amount FROM expenses WHERE 1=1`;
  if (opts.year) {
    params.push(`${opts.year}-`);
    sql += ` AND substr(effective_date, 1, 5) = $${params.length}`;
  }
  if (opts.month) {
    const prefix = `${opts.year}-${opts.month.toString().padStart(2, '0')}-`;
    params[0] = prefix;
    sql = `SELECT amount, excluded, exclusion_amount FROM expenses WHERE substr(effective_date, 1, 8) = $1`;
    if (opts.dayCap) {
      params.push(opts.dayCap.toString().padStart(2, '0'));
      sql += ` AND substr(effective_date, 9, 2) <= $${params.length}`;
    }
  }
  if (opts.personaCode && opts.personaCode !== 'ALL') {
    params.push(opts.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  const rows = await conn.select<{ amount: number; excluded: number; exclusion_amount: number | null }[]>(sql, params);
  let net = 0, gross = 0, excluded = 0;
  for (const r of rows) {
    gross += r.amount;
    if (r.excluded !== 0) {
      excluded += r.amount;
    } else if (r.exclusion_amount && r.exclusion_amount > 0) {
      const e = Math.min(r.amount, r.exclusion_amount);
      excluded += e;
      net += r.amount - e;
    } else {
      net += r.amount;
    }
  }
  return { net, gross, excludedTotal: excluded, count: rows.length };
}
