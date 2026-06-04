import { db, newId, nowIso } from './db';

export interface MapRow {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  viewport_x: number;
  viewport_y: number;
  viewport_zoom: number;
}

export interface Viewport {
  x: number;
  y: number;
  zoom: number;
}

export async function listMaps(): Promise<MapRow[]> {
  const d = await db();
  return d.select<MapRow[]>(
    'SELECT * FROM maps ORDER BY updated_at DESC, created_at DESC',
  );
}

export async function getMap(id: string): Promise<MapRow | null> {
  const d = await db();
  const rows = await d.select<MapRow[]>('SELECT * FROM maps WHERE id = ?', [id]);
  return rows[0] ?? null;
}

export async function createMap(title: string): Promise<MapRow> {
  const d = await db();
  const id = newId();
  const ts = nowIso();
  await d.execute(
    `INSERT INTO maps (id, title, created_at, updated_at, viewport_x, viewport_y, viewport_zoom)
     VALUES (?, ?, ?, ?, 0, 0, 1)`,
    [id, title.trim() || 'Untitled map', ts, ts],
  );
  return {
    id,
    title: title.trim() || 'Untitled map',
    created_at: ts,
    updated_at: ts,
    viewport_x: 0,
    viewport_y: 0,
    viewport_zoom: 1,
  };
}

export async function renameMap(id: string, title: string): Promise<void> {
  const d = await db();
  await d.execute('UPDATE maps SET title = ?, updated_at = ? WHERE id = ?', [
    title.trim() || 'Untitled map',
    nowIso(),
    id,
  ]);
}

/** Bump updated_at so the map floats to the top of the sidebar after edits. */
export async function touchMap(id: string): Promise<void> {
  const d = await db();
  await d.execute('UPDATE maps SET updated_at = ? WHERE id = ?', [nowIso(), id]);
}

export async function saveViewport(id: string, vp: Viewport): Promise<void> {
  const d = await db();
  await d.execute(
    'UPDATE maps SET viewport_x = ?, viewport_y = ?, viewport_zoom = ? WHERE id = ?',
    [vp.x, vp.y, vp.zoom, id],
  );
}

export async function deleteMap(id: string): Promise<void> {
  const d = await db();
  // nodes + edges cascade via the FK in 001_init.sql.
  await d.execute('DELETE FROM maps WHERE id = ?', [id]);
}
