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
  return { adhocTotal, siteTotal, total: adhocTotal + siteTotal };
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
