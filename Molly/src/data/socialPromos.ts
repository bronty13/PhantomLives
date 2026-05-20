import { db } from './db';

export interface SocialPromo {
  id: number;
  personaCode: string | null;
  platformId: number;
  handle: string;
  postedAt: string;            // ISO datetime, e.g. "2026-05-20T19:30:00"
  url: string;
  title: string;
  body: string;
  clipId: string | null;
  notesHtml: string;
  archived: boolean;
  createdAt: string;
  updatedAt: string;
}

interface Row {
  id: number;
  persona_code: string | null;
  platform_id: number;
  handle: string;
  posted_at: string;
  url: string;
  title: string;
  body: string;
  clip_id: string | null;
  notes_html: string;
  archived: number;
  created_at: string;
  updated_at: string;
}

function rowToPromo(r: Row): SocialPromo {
  return {
    id: r.id,
    personaCode: r.persona_code,
    platformId: r.platform_id,
    handle: r.handle,
    postedAt: r.posted_at,
    url: r.url,
    title: r.title,
    body: r.body,
    clipId: r.clip_id,
    notesHtml: r.notes_html,
    archived: r.archived !== 0,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

const SELECT_COLS = `id, persona_code, platform_id, handle, posted_at, url, title, body, clip_id, notes_html, archived, created_at, updated_at`;

export interface PromoFilter {
  personaCode?: string;
  platformId?: number;
  search?: string;
  year?: number;
  month?: number;
  limit?: number;
}

export async function listPromos(filter: PromoFilter = {}): Promise<SocialPromo[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT ${SELECT_COLS} FROM social_promos WHERE archived = 0`;
  if (filter.personaCode && filter.personaCode !== 'ALL') {
    params.push(filter.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  if (filter.platformId) {
    params.push(filter.platformId);
    sql += ` AND platform_id = $${params.length}`;
  }
  if (filter.year) {
    params.push(`${filter.year}-`);
    sql += ` AND substr(posted_at, 1, 5) = $${params.length}`;
  }
  if (filter.year && filter.month) {
    const prefix = `${filter.year}-${filter.month.toString().padStart(2, '0')}-`;
    params.push(prefix);
    sql += ` AND substr(posted_at, 1, 8) = $${params.length}`;
  }
  if (filter.search?.trim()) {
    const like = `%${filter.search.trim()}%`;
    params.push(like, like, like);
    sql += ` AND (title LIKE $${params.length - 2} OR body LIKE $${params.length - 1} OR handle LIKE $${params.length})`;
  }
  sql += ' ORDER BY posted_at DESC, id DESC';
  if (filter.limit) {
    params.push(filter.limit);
    sql += ` LIMIT $${params.length}`;
  }
  const rows = await conn.select<Row[]>(sql, params);
  return rows.map(rowToPromo);
}

export async function getPromo(id: number): Promise<SocialPromo | null> {
  const conn = await db();
  const rows = await conn.select<Row[]>(`SELECT ${SELECT_COLS} FROM social_promos WHERE id = $1`, [id]);
  return rows.length === 0 ? null : rowToPromo(rows[0]);
}

export async function createPromo(p: Omit<SocialPromo, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO social_promos (persona_code, platform_id, handle, posted_at, url, title, body, clip_id, notes_html, archived)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
    [
      p.personaCode, p.platformId, p.handle, p.postedAt, p.url, p.title, p.body,
      p.clipId, p.notesHtml, p.archived ? 1 : 0,
    ],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updatePromo(p: SocialPromo): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE social_promos SET persona_code = $1, platform_id = $2, handle = $3, posted_at = $4, url = $5, title = $6, body = $7, clip_id = $8, notes_html = $9, archived = $10, updated_at = datetime('now') WHERE id = $11`,
    [
      p.personaCode, p.platformId, p.handle, p.postedAt, p.url, p.title, p.body,
      p.clipId, p.notesHtml, p.archived ? 1 : 0, p.id,
    ],
  );
}

export async function deletePromo(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM social_promos WHERE id = $1', [id]);
}

// ---------- Dashboard / report helpers --------------------------------

export interface PromoCount {
  platformId: number;
  count: number;
}

export async function countByPlatform(opts: { year?: number; month?: number; personaCode?: string } = {}): Promise<PromoCount[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT platform_id, COUNT(*) AS n FROM social_promos WHERE archived = 0`;
  if (opts.personaCode && opts.personaCode !== 'ALL') {
    params.push(opts.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  if (opts.year) {
    params.push(`${opts.year}-`);
    sql += ` AND substr(posted_at, 1, 5) = $${params.length}`;
  }
  if (opts.year && opts.month) {
    const prefix = `${opts.year}-${opts.month.toString().padStart(2, '0')}-`;
    params.push(prefix);
    sql += ` AND substr(posted_at, 1, 8) = $${params.length}`;
  }
  sql += ' GROUP BY platform_id ORDER BY n DESC';
  const rows = await conn.select<{ platform_id: number; n: number }[]>(sql, params);
  return rows.map((r) => ({ platformId: r.platform_id, count: r.n }));
}

export async function countTotal(opts: { year?: number; month?: number; personaCode?: string } = {}): Promise<number> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT COUNT(*) AS n FROM social_promos WHERE archived = 0`;
  if (opts.personaCode && opts.personaCode !== 'ALL') {
    params.push(opts.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  if (opts.year) {
    params.push(`${opts.year}-`);
    sql += ` AND substr(posted_at, 1, 5) = $${params.length}`;
  }
  if (opts.year && opts.month) {
    const prefix = `${opts.year}-${opts.month.toString().padStart(2, '0')}-`;
    params.push(prefix);
    sql += ` AND substr(posted_at, 1, 8) = $${params.length}`;
  }
  const rows = await conn.select<{ n: number }[]>(sql, params);
  return rows[0]?.n ?? 0;
}
