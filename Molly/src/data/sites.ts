import { db } from './db';

export interface Site {
  id: number;
  personaCode: string;
  name: string;
  shortCode: string;
  url: string;
  username: string;
  note: string;
  color: string;
  loginGroup: string | null;
  sortOrder: number;
  archived: boolean;
}

interface SiteRow {
  id: number;
  persona_code: string;
  name: string;
  short_code: string;
  url: string;
  username: string;
  note: string;
  color: string;
  login_group: string | null;
  sort_order: number;
  archived: number;
}

function rowToSite(r: SiteRow): Site {
  return {
    id: r.id,
    personaCode: r.persona_code,
    name: r.name,
    shortCode: r.short_code,
    url: r.url,
    username: r.username,
    note: r.note,
    color: r.color,
    loginGroup: r.login_group,
    sortOrder: r.sort_order,
    archived: r.archived !== 0,
  };
}

export async function listSites(opts?: { personaCode?: string }): Promise<Site[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql =
    'SELECT id, persona_code, name, short_code, url, username, note, color, login_group, sort_order, archived FROM sites WHERE archived = 0';
  if (opts?.personaCode && opts.personaCode !== 'ALL') {
    sql += ' AND persona_code = $1';
    params.push(opts.personaCode);
  }
  sql += ' ORDER BY persona_code, sort_order, name';
  const rows = await conn.select<SiteRow[]>(sql, params);
  return rows.map(rowToSite);
}

export async function createSite(s: Omit<Site, 'id'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO sites (persona_code, name, short_code, url, username, note, color, login_group, sort_order, archived)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
    [
      s.personaCode,
      s.name,
      s.shortCode,
      s.url,
      s.username,
      s.note,
      s.color,
      s.loginGroup,
      s.sortOrder,
      s.archived ? 1 : 0,
    ],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updateSite(s: Site): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE sites SET persona_code = $1, name = $2, short_code = $3, url = $4, username = $5, note = $6, color = $7, login_group = $8, sort_order = $9, archived = $10, updated_at = datetime('now') WHERE id = $11`,
    [
      s.personaCode,
      s.name,
      s.shortCode,
      s.url,
      s.username,
      s.note,
      s.color,
      s.loginGroup,
      s.sortOrder,
      s.archived ? 1 : 0,
      s.id,
    ],
  );
}

export async function deleteSite(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM sites WHERE id = $1', [id]);
}
