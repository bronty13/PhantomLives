import { db, newId, nowIso } from './db';

export interface NodeRow {
  id: string;
  map_id: string;
  label: string;
  x: number;
  y: number;
  color: string | null;
  created_at: string;
  updated_at: string;
  /** null = no checkbox · 0 = unchecked · 1 = checked. */
  checked: number | null;
  note: string | null;
  collapsed: number;
  icon: string | null;
}

export async function listNodes(mapId: string): Promise<NodeRow[]> {
  const d = await db();
  return d.select<NodeRow[]>(
    'SELECT * FROM nodes WHERE map_id = ? ORDER BY created_at',
    [mapId],
  );
}

export async function createNode(
  mapId: string,
  label: string,
  x: number,
  y: number,
  color: string | null = null,
): Promise<NodeRow> {
  const d = await db();
  const id = newId();
  const ts = nowIso();
  await d.execute(
    `INSERT INTO nodes (id, map_id, label, x, y, color, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [id, mapId, label, x, y, color, ts, ts],
  );
  return {
    id,
    map_id: mapId,
    label,
    x,
    y,
    color,
    created_at: ts,
    updated_at: ts,
    checked: null,
    note: null,
    collapsed: 0,
    icon: null,
  };
}

export async function updateNodeLabel(id: string, label: string): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET label = ?, updated_at = ? WHERE id = ?', [
    label,
    nowIso(),
    id,
  ]);
}

export async function updateNodeColor(
  id: string,
  color: string | null,
): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET color = ?, updated_at = ? WHERE id = ?', [
    color,
    nowIso(),
    id,
  ]);
}

export async function updateNodePosition(
  id: string,
  x: number,
  y: number,
): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET x = ?, y = ?, updated_at = ? WHERE id = ?', [
    x,
    y,
    nowIso(),
    id,
  ]);
}

/** Persist many positions in one go (used by the auto-layout "Tidy" action). */
export async function updateNodePositions(
  positions: { id: string; x: number; y: number }[],
): Promise<void> {
  const d = await db();
  const ts = nowIso();
  for (const p of positions) {
    await d.execute('UPDATE nodes SET x = ?, y = ?, updated_at = ? WHERE id = ?', [
      p.x,
      p.y,
      ts,
      p.id,
    ]);
  }
}

export async function deleteNode(id: string): Promise<void> {
  const d = await db();
  // incident + outgoing edges cascade via FK.
  await d.execute('DELETE FROM nodes WHERE id = ?', [id]);
}

/** Set the checkbox state: null removes it, 0 = unchecked, 1 = checked. */
export async function setNodeChecked(id: string, checked: number | null): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET checked = ?, updated_at = ? WHERE id = ?', [
    checked,
    nowIso(),
    id,
  ]);
}

export async function setNodeNote(id: string, note: string | null): Promise<void> {
  const d = await db();
  const value = note && note.trim() ? note : null;
  await d.execute('UPDATE nodes SET note = ?, updated_at = ? WHERE id = ?', [
    value,
    nowIso(),
    id,
  ]);
}

export async function setNodeCollapsed(id: string, collapsed: boolean): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET collapsed = ?, updated_at = ? WHERE id = ?', [
    collapsed ? 1 : 0,
    nowIso(),
    id,
  ]);
}

export async function setNodeIcon(id: string, icon: string | null): Promise<void> {
  const d = await db();
  await d.execute('UPDATE nodes SET icon = ?, updated_at = ? WHERE id = ?', [
    icon || null,
    nowIso(),
    id,
  ]);
}
