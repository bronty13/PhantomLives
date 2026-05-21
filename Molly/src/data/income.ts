import { db } from './db';

// ---------- Adhoc income --------------------------------------------------

export interface AdhocIncome {
  id: number;
  dateEarned: string;          // ISO date YYYY-MM-DD
  amount: number;
  personaCode: string | null;
  sourceLabel: string;
  note: string;
  createdAt: string;
  updatedAt: string;
}

interface AdhocRow {
  id: number;
  date_earned: string;
  amount: number;
  persona_code: string | null;
  source_label: string;
  note: string;
  created_at: string;
  updated_at: string;
}

function rowToAdhoc(r: AdhocRow): AdhocIncome {
  return {
    id: r.id,
    dateEarned: r.date_earned,
    amount: r.amount,
    personaCode: r.persona_code,
    sourceLabel: r.source_label,
    note: r.note,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export interface AdhocFilter {
  year?: number;
  month?: number;              // 1-12, requires year
  personaCode?: string;
}

export async function listAdhoc(filter: AdhocFilter = {}): Promise<AdhocIncome[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT id, date_earned, amount, persona_code, source_label, note, created_at, updated_at FROM income_adhoc WHERE 1=1`;
  if (filter.year) {
    params.push(`${filter.year}-`);
    sql += ` AND substr(date_earned, 1, 5) = $${params.length}`;
  }
  if (filter.year && filter.month) {
    const prefix = `${filter.year}-${filter.month.toString().padStart(2, '0')}-`;
    params.push(prefix);
    sql += ` AND substr(date_earned, 1, 8) = $${params.length}`;
  }
  if (filter.personaCode && filter.personaCode !== 'ALL') {
    params.push(filter.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  sql += ` ORDER BY date_earned DESC, id DESC`;
  const rows = await conn.select<AdhocRow[]>(sql, params);
  return rows.map(rowToAdhoc);
}

export async function createAdhoc(input: Omit<AdhocIncome, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO income_adhoc (date_earned, amount, persona_code, source_label, note) VALUES ($1, $2, $3, $4, $5)`,
    [input.dateEarned, input.amount, input.personaCode, input.sourceLabel, input.note],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updateAdhoc(input: AdhocIncome): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE income_adhoc SET date_earned = $1, amount = $2, persona_code = $3, source_label = $4, note = $5, updated_at = datetime('now') WHERE id = $6`,
    [input.dateEarned, input.amount, input.personaCode, input.sourceLabel, input.note, input.id],
  );
}

export async function deleteAdhoc(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM income_adhoc WHERE id = $1', [id]);
}

// ---------- Unified adhoc income (adhoc + customer sales) -----------------
//
// 1.5.0: surface customer_sales rows in the Adhoc Income view so all
// one-off income lives in one place. Sales stay in customer_sales as the
// source of truth — this is a read-only union at query time, not a copy.
// Sale rows on the income side are NOT editable; the customer's history
// timeline owns their lifecycle.

export interface UnifiedAdhocAdhoc {
  source: 'adhoc';
  /** income_adhoc row id */
  id: number;
  dateEarned: string;
  amount: number;
  personaCode: string | null;
  sourceLabel: string;
  note: string;
}

export interface UnifiedAdhocSale {
  source: 'sale';
  /** customer_sales row id */
  id: number;
  dateEarned: string;            // sale_date, normalized to YYYY-MM-DD
  amount: number;                // total_cents / 100
  personaCode: string | null;    // customer's persona
  sourceLabel: string;           // "Customer username — Product name"
  note: string;                  // sale.notes
  customerUid: string;
  quantity: number;
  unit: string;
}

export type UnifiedAdhocRow = UnifiedAdhocAdhoc | UnifiedAdhocSale;

interface SaleAsIncomeRow {
  id: number;
  sale_date: string;
  total_cents: number;
  persona_code: string | null;
  customer_uid: string;
  customer_username: string;
  customer_real_name: string;
  product_name: string;
  product_unit: string;
  quantity: number;
  notes: string;
}

export async function listAdhocUnified(filter: AdhocFilter = {}): Promise<UnifiedAdhocRow[]> {
  const conn = await db();
  const adhoc = await listAdhoc(filter);

  // Mirror the same year/month/persona predicates as listAdhoc, but
  // against customer_sales joined with customers + products.
  const saleParams: unknown[] = [];
  let saleSql = `
    SELECT s.id, s.sale_date, s.total_cents, s.quantity, s.notes,
           c.persona_code, c.uid AS customer_uid, c.username AS customer_username,
           c.real_name AS customer_real_name,
           p.name AS product_name, p.unit AS product_unit
      FROM customer_sales s
      JOIN customers c ON c.uid = s.customer_uid
      JOIN products  p ON p.id  = s.product_id
     WHERE 1=1`;
  if (filter.year) {
    saleParams.push(`${filter.year}-`);
    saleSql += ` AND substr(s.sale_date, 1, 5) = $${saleParams.length}`;
  }
  if (filter.year && filter.month) {
    const prefix = `${filter.year}-${filter.month.toString().padStart(2, '0')}-`;
    saleParams.push(prefix);
    saleSql += ` AND substr(s.sale_date, 1, 8) = $${saleParams.length}`;
  }
  if (filter.personaCode && filter.personaCode !== 'ALL') {
    saleParams.push(filter.personaCode);
    saleSql += ` AND c.persona_code = $${saleParams.length}`;
  }
  saleSql += ` ORDER BY s.sale_date DESC, s.id DESC`;
  const saleRows = await conn.select<SaleAsIncomeRow[]>(saleSql, saleParams);

  const sales: UnifiedAdhocSale[] = saleRows.map((r) => {
    const name = r.customer_username?.trim() || r.customer_real_name?.trim() || '(unnamed)';
    return {
      source: 'sale',
      id: r.id,
      dateEarned: (r.sale_date ?? '').split(/[ T]/)[0] ?? '',
      amount: (r.total_cents ?? 0) / 100,
      personaCode: r.persona_code,
      sourceLabel: `${name} — ${r.product_name}`,
      note: r.notes ?? '',
      customerUid: r.customer_uid,
      quantity: r.quantity,
      unit: r.product_unit ?? 'item',
    };
  });

  const adhocs: UnifiedAdhocAdhoc[] = adhoc.map((a) => ({
    source: 'adhoc',
    id: a.id,
    dateEarned: a.dateEarned,
    amount: a.amount,
    personaCode: a.personaCode,
    sourceLabel: a.sourceLabel,
    note: a.note,
  }));

  return [...adhocs, ...sales].sort((a, b) => {
    if (a.dateEarned === b.dateEarned) return b.id - a.id;
    return b.dateEarned.localeCompare(a.dateEarned);
  });
}

// ---------- Site income ---------------------------------------------------

export interface SiteIncome {
  id: number;
  year: number;
  month: number;
  siteId: number;
  amount: number;
  note: string;
}

interface SiteRow {
  id: number;
  year: number;
  month: number;
  site_id: number;
  amount: number;
  note: string;
}

function rowToSite(r: SiteRow): SiteIncome {
  return { id: r.id, year: r.year, month: r.month, siteId: r.site_id, amount: r.amount, note: r.note };
}

export async function listSiteIncome(year: number, month: number): Promise<SiteIncome[]> {
  const conn = await db();
  const rows = await conn.select<SiteRow[]>(
    'SELECT id, year, month, site_id, amount, note FROM income_site WHERE year = $1 AND month = $2',
    [year, month],
  );
  return rows.map(rowToSite);
}

/** Upsert site income for a (year, month, site). Pass 0 to clear. */
export async function upsertSiteIncome(year: number, month: number, siteId: number, amount: number, note = ''): Promise<void> {
  const conn = await db();
  await conn.execute(
    `INSERT INTO income_site (year, month, site_id, amount, note) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT(year, month, site_id) DO UPDATE SET amount = excluded.amount, note = excluded.note, updated_at = datetime('now')`,
    [year, month, siteId, amount, note],
  );
}

export async function deleteSiteIncome(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM income_site WHERE id = $1', [id]);
}

// ---------- Totals (for Reports + Home) ----------------------------------

export interface IncomeTotals {
  adhocTotal: number;
  siteTotal: number;
  total: number;
}

async function sumAdhoc(conn: Awaited<ReturnType<typeof db>>, where: string, params: unknown[]): Promise<number> {
  const rows = await conn.select<{ s: number | null }[]>(`SELECT COALESCE(SUM(amount), 0) AS s FROM income_adhoc WHERE ${where}`, params);
  return rows[0]?.s ?? 0;
}

async function sumSite(conn: Awaited<ReturnType<typeof db>>, where: string, params: unknown[]): Promise<number> {
  const rows = await conn.select<{ s: number | null }[]>(`SELECT COALESCE(SUM(amount), 0) AS s FROM income_site WHERE ${where}`, params);
  return rows[0]?.s ?? 0;
}

function personaClause(table: 'adhoc' | 'site', personaCode: string | undefined, offset: number): { where: string; params: unknown[] } {
  if (!personaCode || personaCode === 'ALL') return { where: '', params: [] };
  if (table === 'adhoc') {
    return { where: ` AND persona_code = $${offset + 1}`, params: [personaCode] };
  }
  // site income joins through sites.persona_code
  return {
    where: ` AND site_id IN (SELECT id FROM sites WHERE persona_code = $${offset + 1})`,
    params: [personaCode],
  };
}

export async function totalsForPeriod(opts: { year: number; month?: number; dayCap?: number; personaCode?: string }): Promise<IncomeTotals> {
  const conn = await db();
  const yearPrefix = `${opts.year}-`;
  let adhocWhere = `substr(date_earned, 1, 5) = $1`;
  const adhocParams: unknown[] = [yearPrefix];

  let siteWhere = `year = $1`;
  const siteParams: unknown[] = [opts.year];

  if (opts.month) {
    const monthPrefix = `${opts.year}-${opts.month.toString().padStart(2, '0')}-`;
    adhocWhere = `substr(date_earned, 1, 8) = $1`;
    adhocParams[0] = monthPrefix;
    if (opts.dayCap) {
      adhocWhere += ` AND substr(date_earned, 9, 2) <= $2`;
      adhocParams.push(opts.dayCap.toString().padStart(2, '0'));
    }
    siteWhere = `year = $1 AND month = $2`;
    siteParams.push(opts.month);
  }

  const adhocP = personaClause('adhoc', opts.personaCode, adhocParams.length);
  const siteP  = personaClause('site',  opts.personaCode, siteParams.length);

  const adhocTotal = await sumAdhoc(conn, adhocWhere + adhocP.where, [...adhocParams, ...adhocP.params]);
  const siteTotal  = await sumSite(conn,  siteWhere  + siteP.where,  [...siteParams,  ...siteP.params]);

  // customer_sales also contributes to the "adhoc" bucket — same conceptual
  // category (one-off income tied to a date), just sourced from customer
  // records instead of typed into the Adhoc Income view directly. We sum
  // total_cents (stored as INTEGER cents) and divide by 100 to land in the
  // same dollars-as-REAL space as income_adhoc.amount.
  const salesParams: unknown[] = [];
  let salesWhere: string;
  if (opts.month) {
    const monthPrefix = `${opts.year}-${opts.month.toString().padStart(2, '0')}-`;
    salesParams.push(monthPrefix);
    salesWhere = `substr(s.sale_date, 1, 8) = $1`;
    if (opts.dayCap) {
      salesParams.push(opts.dayCap.toString().padStart(2, '0'));
      salesWhere += ` AND substr(s.sale_date, 9, 2) <= $2`;
    }
  } else {
    salesParams.push(yearPrefix);
    salesWhere = `substr(s.sale_date, 1, 5) = $1`;
  }
  if (opts.personaCode && opts.personaCode !== 'ALL') {
    salesParams.push(opts.personaCode);
    salesWhere += ` AND c.persona_code = $${salesParams.length}`;
  }
  const salesRows = await conn.select<{ s: number | null }[]>(
    `SELECT COALESCE(SUM(s.total_cents), 0) AS s
       FROM customer_sales s JOIN customers c ON c.uid = s.customer_uid
      WHERE ${salesWhere}`,
    salesParams,
  );
  const salesTotal = (salesRows[0]?.s ?? 0) / 100;

  const combinedAdhoc = adhocTotal + salesTotal;
  return { adhocTotal: combinedAdhoc, siteTotal, total: combinedAdhoc + siteTotal };
}

export interface PerSiteIncome {
  siteId: number;
  siteName: string;
  shortCode: string;
  personaCode: string;
  color: string;
  total: number;
}

export async function perSiteForYear(year: number, personaCode?: string): Promise<PerSiteIncome[]> {
  const conn = await db();
  const params: unknown[] = [year];
  let sql = `
    SELECT s.id AS site_id, s.name, s.short_code, s.persona_code, s.color,
           COALESCE(SUM(i.amount), 0) AS total
    FROM sites s
    LEFT JOIN income_site i ON i.site_id = s.id AND i.year = $1
    WHERE s.archived = 0`;
  if (personaCode && personaCode !== 'ALL') {
    params.push(personaCode);
    sql += ` AND s.persona_code = $${params.length}`;
  }
  sql += ' GROUP BY s.id, s.name, s.short_code, s.persona_code, s.color ORDER BY total DESC, s.name';
  const rows = await conn.select<{
    site_id: number; name: string; short_code: string; persona_code: string; color: string; total: number;
  }[]>(sql, params);
  return rows.map((r) => ({
    siteId: r.site_id,
    siteName: r.name,
    shortCode: r.short_code,
    personaCode: r.persona_code,
    color: r.color,
    total: r.total,
  }));
}
