import { db } from '../data/db';

/**
 * Generate the next customer UID, mirroring the format MasterClipper
 * uses for clip IDs (`YYYY-MM-DD-#####`) so cross-tool IDs are
 * recognizably the same shape. The sequence resets each day; we find
 * the current max by querying the customers table for today's prefix.
 *
 * Reference: `MasterClipper/Sources/MasterClipper/Services/IDGeneratorService.swift`.
 */
export async function nextCustomerUid(date: Date = new Date()): Promise<string> {
  const prefix = formatDateKey(date);
  const conn = await db();
  const rows = await conn.select<{ uid: string }[]>(
    "SELECT uid FROM customers WHERE uid LIKE $1 || '%' ORDER BY uid DESC LIMIT 1",
    [`${prefix}-`],
  );
  let next = 1;
  if (rows.length > 0) {
    const parsed = parseInt(rows[0].uid.slice(prefix.length + 1), 10);
    if (Number.isFinite(parsed)) next = parsed + 1;
  }
  return `${prefix}-${next.toString().padStart(5, '0')}`;
}

/** `YYYY-MM-DD` in the system's local time (matches MasterClipper). */
export function formatDateKey(date: Date): string {
  const y = date.getFullYear().toString().padStart(4, '0');
  const m = (date.getMonth() + 1).toString().padStart(2, '0');
  const d = date.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${d}`;
}
