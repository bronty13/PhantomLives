import { db, newId } from './db';

export interface EdgeRow {
  id: string;
  map_id: string;
  source_id: string;
  target_id: string;
}

export async function listEdges(mapId: string): Promise<EdgeRow[]> {
  const d = await db();
  return d.select<EdgeRow[]>('SELECT * FROM edges WHERE map_id = ?', [mapId]);
}

export async function createEdge(
  mapId: string,
  sourceId: string,
  targetId: string,
): Promise<EdgeRow | null> {
  if (sourceId === targetId) return null;
  const d = await db();
  // Collapse duplicate connections (either direction) to keep the graph clean.
  const existing = await d.select<EdgeRow[]>(
    `SELECT * FROM edges WHERE map_id = ?
       AND ((source_id = ? AND target_id = ?) OR (source_id = ? AND target_id = ?))`,
    [mapId, sourceId, targetId, targetId, sourceId],
  );
  if (existing.length > 0) return existing[0];

  const id = newId();
  await d.execute(
    'INSERT INTO edges (id, map_id, source_id, target_id) VALUES (?, ?, ?, ?)',
    [id, mapId, sourceId, targetId],
  );
  return { id, map_id: mapId, source_id: sourceId, target_id: targetId };
}

export async function deleteEdge(id: string): Promise<void> {
  const d = await db();
  await d.execute('DELETE FROM edges WHERE id = ?', [id]);
}
