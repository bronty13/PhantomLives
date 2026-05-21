// Molly's Log — global creator-facing journal. Same shape as
// customer_history (timestamped entry + optional inline BLOB attachment)
// but without a customer FK. Full CRUD; attachments go through Rust /
// rusqlite so binary bytes never round-trip through JS IPC.
import { invoke } from '@tauri-apps/api/core';
import { db } from './db';

export interface LogEntry {
  id: number;
  ts: string;
  body: string;
  attachmentFilename: string;
  attachmentMime: string;
  attachmentSize: number;
  hasAttachment: boolean;
  updatedAt: string;
}

interface LogRow {
  id: number;
  ts: string;
  body: string;
  attachment_filename: string;
  attachment_mime: string;
  attachment_size: number;
  updated_at: string;
}

function rowToEntry(r: LogRow): LogEntry {
  return {
    id: r.id,
    ts: r.ts,
    body: r.body,
    attachmentFilename: r.attachment_filename ?? '',
    attachmentMime: r.attachment_mime ?? '',
    attachmentSize: r.attachment_size ?? 0,
    hasAttachment: (r.attachment_size ?? 0) > 0,
    updatedAt: r.updated_at,
  };
}

/**
 * List all log entries, newest first. BLOB column is deliberately not
 * selected — only metadata travels into JS. Bodies render inline.
 */
export async function listEntries(): Promise<LogEntry[]> {
  const conn = await db();
  const rows = await conn.select<LogRow[]>(
    `SELECT id, ts, body, attachment_filename, attachment_mime, attachment_size, updated_at
       FROM mollys_log
       ORDER BY ts DESC, id DESC`,
  );
  return rows.map(rowToEntry);
}

/** Append a text-only log entry. */
export async function addEntry(body: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    `INSERT INTO mollys_log (body) VALUES ($1)`,
    [body],
  );
}

/** Append a log entry with an attached file (BLOB), via Rust + rusqlite. */
export async function addEntryWithAttachment(body: string, srcPath: string): Promise<{ id: number }> {
  return await invoke<{ id: number }>('add_log_entry_with_attachment', { body, srcPath });
}

/** Revise a log entry's body. Attachment metadata + BLOB are untouched. */
export async function updateEntry(entryId: number, body: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE mollys_log SET body = $1, updated_at = datetime('now') WHERE id = $2`,
    [body, entryId],
  );
}

/** Remove a log entry. Cascades the attachment BLOB with it. */
export async function deleteEntry(entryId: number): Promise<void> {
  const conn = await db();
  await conn.execute(`DELETE FROM mollys_log WHERE id = $1`, [entryId]);
}

/** Stream the BLOB out to a user-chosen target path. */
export async function downloadAttachment(logId: number, targetPath: string): Promise<void> {
  await invoke('download_log_attachment', { logId, targetPath });
}
