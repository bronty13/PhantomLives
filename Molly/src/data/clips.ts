import { db } from './db';

export interface Clip {
  id: string;                    // MasterClipper UID, e.g. "2026-05-20-00001"
  externalClipId: string;
  personaCode: string | null;
  title: string;
  status: string;
  contentDate: string | null;
  goLiveDate: string | null;
  length: string;
  price: string;
  categories: string;
  keywords: string;
  performers: string;
  notes: string;                 // imported from MC
  mollyNotesHtml: string;        // editable; preserved across re-imports
  importedAt: string;
}

interface ClipRow {
  id: string;
  external_clip_id: string;
  persona_code: string | null;
  title: string;
  status: string;
  content_date: string | null;
  go_live_date: string | null;
  length: string;
  price: string;
  categories: string;
  keywords: string;
  performers: string;
  notes: string;
  molly_notes_html: string;
  imported_at: string;
}

function rowToClip(r: ClipRow): Clip {
  return {
    id: r.id,
    externalClipId: r.external_clip_id,
    personaCode: r.persona_code,
    title: r.title,
    status: r.status,
    contentDate: r.content_date,
    goLiveDate: r.go_live_date,
    length: r.length,
    price: r.price,
    categories: r.categories,
    keywords: r.keywords,
    performers: r.performers,
    notes: r.notes,
    mollyNotesHtml: r.molly_notes_html,
    importedAt: r.imported_at,
  };
}

export interface ListClipsOpts {
  personaCode?: string;
  search?: string;
  from?: string;            // ISO date — go_live_date >=
  to?: string;              // ISO date — go_live_date <=
  withGoLiveOnly?: boolean;
  limit?: number;
}

export async function listClips(opts: ListClipsOpts = {}): Promise<Clip[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql =
    `SELECT id, external_clip_id, persona_code, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes, molly_notes_html, imported_at
     FROM clips WHERE 1=1`;
  if (opts.personaCode && opts.personaCode !== 'ALL') {
    params.push(opts.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  if (opts.withGoLiveOnly) sql += ' AND go_live_date IS NOT NULL';
  if (opts.from) {
    params.push(opts.from);
    sql += ` AND substr(go_live_date, 1, 10) >= $${params.length}`;
  }
  if (opts.to) {
    params.push(opts.to);
    sql += ` AND substr(go_live_date, 1, 10) <= $${params.length}`;
  }
  if (opts.search?.trim()) {
    const like = `%${opts.search.trim()}%`;
    params.push(like, like, like);
    sql += ` AND (id LIKE $${params.length - 2} OR title LIKE $${params.length - 1} OR keywords LIKE $${params.length})`;
  }
  sql += ' ORDER BY COALESCE(go_live_date, content_date, imported_at) DESC';
  if (opts.limit) {
    params.push(opts.limit);
    sql += ` LIMIT $${params.length}`;
  }
  const rows = await conn.select<ClipRow[]>(sql, params);
  return rows.map(rowToClip);
}

export async function getClip(id: string): Promise<Clip | null> {
  const conn = await db();
  const rows = await conn.select<ClipRow[]>(
    `SELECT id, external_clip_id, persona_code, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes, molly_notes_html, imported_at
     FROM clips WHERE id = $1`,
    [id],
  );
  return rows.length === 0 ? null : rowToClip(rows[0]);
}

/**
 * Insert a fresh import, or update existing row by id. Preserves the
 * existing `molly_notes_html` (never overwritten by import). Returns
 * "inserted" or "updated".
 *
 * Implementation: `INSERT OR IGNORE` first; if `rowsAffected` is 0 the
 * row already existed and we do a targeted UPDATE. Fresh-import rows
 * cost one IPC round-trip; re-imports cost two. (Previous design did a
 * SELECT-first and always took two — that compounded into multi-second
 * stalls on large exports.) We intentionally leave `molly_notes_html`
 * untouched on UPDATE so user edits survive re-import.
 */
export async function upsertClip(c: Omit<Clip, 'mollyNotesHtml' | 'importedAt'>): Promise<'inserted' | 'updated'> {
  const conn = await db();
  const ins = await conn.execute(
    `INSERT OR IGNORE INTO clips (id, external_clip_id, persona_code, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
    [
      c.id, c.externalClipId, c.personaCode, c.title, c.status, c.contentDate, c.goLiveDate,
      c.length, c.price, c.categories, c.keywords, c.performers, c.notes,
    ],
  );
  if (ins.rowsAffected && ins.rowsAffected > 0) {
    return 'inserted';
  }
  await conn.execute(
    `UPDATE clips SET external_clip_id = $1, persona_code = $2, title = $3, status = $4, content_date = $5, go_live_date = $6, length = $7, price = $8, categories = $9, keywords = $10, performers = $11, notes = $12, imported_at = datetime('now') WHERE id = $13`,
    [
      c.externalClipId, c.personaCode, c.title, c.status, c.contentDate, c.goLiveDate,
      c.length, c.price, c.categories, c.keywords, c.performers, c.notes, c.id,
    ],
  );
  return 'updated';
}

export async function updateClipNotes(id: string, mollyNotesHtml: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    "UPDATE clips SET molly_notes_html = $1 WHERE id = $2",
    [mollyNotesHtml, id],
  );
}

export async function deleteClip(id: string): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM clips WHERE id = $1', [id]);
}

// ------------------- Dashboard / reporting queries ------------------------

export interface ClipImportLog {
  id: number;
  importedAt: string;
  sourceFile: string;
  rowsTotal: number;
  rowsInserted: number;
  rowsUpdated: number;
  rowsSkipped: number;
  note: string;
}

export async function logImport(entry: Omit<ClipImportLog, 'id' | 'importedAt'>): Promise<void> {
  const conn = await db();
  await conn.execute(
    `INSERT INTO clip_imports (source_file, rows_total, rows_inserted, rows_updated, rows_skipped, note)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [entry.sourceFile, entry.rowsTotal, entry.rowsInserted, entry.rowsUpdated, entry.rowsSkipped, entry.note],
  );
}

export async function recentImports(limit = 5): Promise<ClipImportLog[]> {
  const conn = await db();
  const rows = await conn.select<{
    id: number;
    imported_at: string;
    source_file: string;
    rows_total: number;
    rows_inserted: number;
    rows_updated: number;
    rows_skipped: number;
    note: string;
  }[]>(
    'SELECT id, imported_at, source_file, rows_total, rows_inserted, rows_updated, rows_skipped, note FROM clip_imports ORDER BY id DESC LIMIT $1',
    [limit],
  );
  return rows.map((r) => ({
    id: r.id,
    importedAt: r.imported_at,
    sourceFile: r.source_file,
    rowsTotal: r.rows_total,
    rowsInserted: r.rows_inserted,
    rowsUpdated: r.rows_updated,
    rowsSkipped: r.rows_skipped,
    note: r.note,
  }));
}

export interface ClipCounts {
  mtd: number;
  priorMtd: number;
  ytd: number;
  total: number;
}

/**
 * Count clips whose go_live_date falls in (a) current month, (b) the
 * same month last year for prior-MTD comparison... actually "prior MTD"
 * commonly means previous month's MTD-equivalent slice. We use the
 * previous calendar month for clarity (Jan vs Feb-so-far is misleading,
 * but for a content creator's monthly cadence the standard is the prior
 * calendar month). `personaCode` optional filter.
 */
export async function clipCounts(personaCode?: string): Promise<ClipCounts> {
  const conn = await db();
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth() + 1; // 1-12
  const d = now.getDate();
  const ym  = `${y}-${m.toString().padStart(2, '0')}`;
  const prevMonth = m === 1 ? 12 : m - 1;
  const prevY     = m === 1 ? y - 1 : y;
  const prevYm = `${prevY}-${prevMonth.toString().padStart(2, '0')}`;
  const yearKey = `${y}-`;

  const params: unknown[] = [];
  const where = (extra: string) => {
    if (personaCode && personaCode !== 'ALL') {
      params.push(personaCode);
      return `${extra} AND persona_code = $${params.length}`;
    }
    return extra;
  };

  // Count by prefix on go_live_date (string "YYYY-MM-..."), with day cap
  // for MTD (today's day-of-month) so the comparison is apples-to-apples.
  const totalRows = await conn.select<{ n: number }[]>(
    `SELECT COUNT(*) AS n FROM clips WHERE 1=1 ${personaCode && personaCode !== 'ALL' ? `AND persona_code = '${personaCode.replace(/'/g, "''")}'` : ''}`,
  );

  // MTD this year
  const mtdParams: unknown[] = [`${ym}-%`];
  let mtdSql = `SELECT COUNT(*) AS n FROM clips WHERE substr(go_live_date,1,7) = substr($1, 1, 7)`;
  if (personaCode && personaCode !== 'ALL') {
    mtdParams.push(personaCode);
    mtdSql += ` AND persona_code = $${mtdParams.length}`;
  }
  const mtdRows = await conn.select<{ n: number }[]>(mtdSql, mtdParams);

  // Prior month MTD-equivalent: same day-of-month slice
  const dayCap = d.toString().padStart(2, '0');
  const priorParams: unknown[] = [prevYm, dayCap];
  let priorSql = `SELECT COUNT(*) AS n FROM clips WHERE substr(go_live_date,1,7) = $1 AND substr(go_live_date,9,2) <= $2`;
  if (personaCode && personaCode !== 'ALL') {
    priorParams.push(personaCode);
    priorSql += ` AND persona_code = $${priorParams.length}`;
  }
  const priorRows = await conn.select<{ n: number }[]>(priorSql, priorParams);

  // YTD
  const ytdParams: unknown[] = [yearKey];
  let ytdSql = `SELECT COUNT(*) AS n FROM clips WHERE substr(go_live_date,1,5) = $1`;
  if (personaCode && personaCode !== 'ALL') {
    ytdParams.push(personaCode);
    ytdSql += ` AND persona_code = $${ytdParams.length}`;
  }
  const ytdRows = await conn.select<{ n: number }[]>(ytdSql, ytdParams);

  // Silence unused warnings — params are wired through above.
  void where;
  void params;

  return {
    mtd:      mtdRows[0]?.n ?? 0,
    priorMtd: priorRows[0]?.n ?? 0,
    ytd:      ytdRows[0]?.n ?? 0,
    total:    totalRows[0]?.n ?? 0,
  };
}

export interface PersonaCount {
  personaCode: string | null;
  count: number;
}

export async function countByPersona(): Promise<PersonaCount[]> {
  const conn = await db();
  const rows = await conn.select<{ persona_code: string | null; n: number }[]>(
    'SELECT persona_code, COUNT(*) AS n FROM clips GROUP BY persona_code ORDER BY n DESC',
  );
  return rows.map((r) => ({ personaCode: r.persona_code, count: r.n }));
}

export interface ReuseGroup {
  reason: 'external_id' | 'title_window';
  key: string;             // external_clip_id or title
  count: number;
  clips: Clip[];
}

/**
 * Detect potentially-reused content:
 *   1) clips sharing the same non-empty external_clip_id (likely same source asset reposted)
 *   2) clips sharing the same title where go_live_dates fall within `windowDays`
 *      of each other.
 */
export async function detectReuse(windowDays = 14, limit = 25): Promise<ReuseGroup[]> {
  const conn = await db();
  const groups: ReuseGroup[] = [];

  // (1) external_clip_id collisions
  const ext = await conn.select<{ external_clip_id: string; n: number }[]>(
    "SELECT external_clip_id, COUNT(*) AS n FROM clips WHERE external_clip_id != '' GROUP BY external_clip_id HAVING n > 1 ORDER BY n DESC LIMIT $1",
    [limit],
  );
  for (const e of ext) {
    const dups = await listClips({ search: undefined });
    // We need clips with that external id; do a targeted query instead.
    const all = await conn.select<ClipRow[]>(
      `SELECT id, external_clip_id, persona_code, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes, molly_notes_html, imported_at
       FROM clips WHERE external_clip_id = $1 ORDER BY go_live_date DESC`,
      [e.external_clip_id],
    );
    groups.push({ reason: 'external_id', key: e.external_clip_id, count: e.n, clips: all.map(rowToClip) });
    void dups;
  }

  // (2) title duplicates within window
  const titles = await conn.select<{ title: string; n: number }[]>(
    "SELECT title, COUNT(*) AS n FROM clips WHERE title != '' GROUP BY title HAVING n > 1 ORDER BY n DESC LIMIT $1",
    [limit],
  );
  for (const t of titles) {
    const all = await conn.select<ClipRow[]>(
      `SELECT id, external_clip_id, persona_code, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes, molly_notes_html, imported_at
       FROM clips WHERE title = $1 ORDER BY go_live_date DESC`,
      [t.title],
    );
    // Filter to groups whose go_live_dates span <= windowDays.
    const dates = all
      .map((r) => (r.go_live_date ? r.go_live_date.slice(0, 10) : null))
      .filter((d): d is string => !!d);
    if (dates.length >= 2) {
      const min = new Date(dates[dates.length - 1] + 'T00:00:00').getTime();
      const max = new Date(dates[0] + 'T00:00:00').getTime();
      const spanDays = Math.abs((max - min) / 86_400_000);
      if (spanDays <= windowDays) {
        groups.push({ reason: 'title_window', key: t.title, count: t.n, clips: all.map(rowToClip) });
      }
    }
  }

  return groups;
}
