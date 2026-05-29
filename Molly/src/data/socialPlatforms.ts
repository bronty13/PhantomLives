import { db } from './db';

export interface SocialPlatform {
  id: number;
  name: string;
  shortCode: string;
  icon: string;
  color: string;
  sortOrder: number;
  archived: boolean;
  dailyGoal: number;
}

interface Row {
  id: number;
  name: string;
  short_code: string;
  icon: string;
  color: string;
  sort_order: number;
  archived: number;
  daily_goal: number;
}

function rowToPlatform(r: Row): SocialPlatform {
  return {
    id: r.id,
    name: r.name,
    shortCode: r.short_code,
    icon: r.icon,
    color: r.color,
    sortOrder: r.sort_order,
    archived: r.archived !== 0,
    dailyGoal: r.daily_goal ?? 1,
  };
}

export async function listPlatforms(): Promise<SocialPlatform[]> {
  const conn = await db();
  const rows = await conn.select<Row[]>(
    'SELECT id, name, short_code, icon, color, sort_order, archived, daily_goal FROM social_platforms WHERE archived = 0 ORDER BY sort_order, name',
  );
  return rows.map(rowToPlatform);
}

export async function createPlatform(p: Omit<SocialPlatform, 'id'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO social_platforms (name, short_code, icon, color, sort_order, archived, daily_goal) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [p.name, p.shortCode, p.icon, p.color, p.sortOrder, p.archived ? 1 : 0, p.dailyGoal],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updatePlatform(p: SocialPlatform): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE social_platforms SET name = $1, short_code = $2, icon = $3, color = $4, sort_order = $5, archived = $6, daily_goal = $7, updated_at = datetime('now') WHERE id = $8`,
    [p.name, p.shortCode, p.icon, p.color, p.sortOrder, p.archived ? 1 : 0, p.dailyGoal, p.id],
  );
}

export async function deletePlatform(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM social_platforms WHERE id = $1', [id]);
}
