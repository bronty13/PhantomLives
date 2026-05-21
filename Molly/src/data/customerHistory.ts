// Per-customer history log. As of 1.4.2 entries are full-CRUD — the
// original audit-only design was lifted at the user's request. Attachments
// still live as SQLite BLOBs (migration 013); editing a note's body does
// not touch the attachment column, and deleting a note removes its
// attachment along with the row.
//
// Writes that include a file go through the
// `add_history_entry_with_attachment` Tauri command (rusqlite, BLOB
// binding); plain text-only entries are inserted/updated/deleted via
// tauri-plugin-sql below.
import { invoke } from '@tauri-apps/api/core';
import { db } from './db';

export interface HistoryEntry {
  id: number;
  customerUid: string;
  ts: string;             // ISO datetime from SQLite's datetime('now')
  body: string;
  attachmentFilename: string;
  attachmentMime: string;
  attachmentSize: number; // bytes; 0 = no attachment
  hasAttachment: boolean; // derived
}

interface HistoryRow {
  id: number;
  customer_uid: string;
  ts: string;
  body: string;
  attachment_filename: string;
  attachment_mime: string;
  attachment_size: number;
}

function rowToEntry(r: HistoryRow): HistoryEntry {
  return {
    id: r.id,
    customerUid: r.customer_uid,
    ts: r.ts,
    body: r.body,
    attachmentFilename: r.attachment_filename ?? '',
    attachmentMime: r.attachment_mime ?? '',
    attachmentSize: r.attachment_size ?? 0,
    hasAttachment: (r.attachment_size ?? 0) > 0,
  };
}

/**
 * List a customer's history entries, newest first. The BLOB column is
 * deliberately NOT selected — we read metadata only here so the page can
 * render hundreds of entries cheaply, then stream the BLOB out by id when
 * the user clicks an attachment.
 */
export async function listEntries(customerUid: string): Promise<HistoryEntry[]> {
  const conn = await db();
  const rows = await conn.select<HistoryRow[]>(
    `SELECT id, customer_uid, ts, body, attachment_filename, attachment_mime, attachment_size
       FROM customer_history
      WHERE customer_uid = $1
      ORDER BY ts DESC, id DESC`,
    [customerUid],
  );
  return rows.map(rowToEntry);
}

/**
 * Append a text-only history entry. Use `addEntryWithAttachment` instead
 * when the user picked a file.
 */
export async function addEntry(customerUid: string, body: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    `INSERT INTO customer_history (customer_uid, body) VALUES ($1, $2)`,
    [customerUid, body],
  );
}

/** Revise a note's body. Attachment metadata + BLOB are untouched. */
export async function updateEntry(entryId: number, body: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE customer_history SET body = $1 WHERE id = $2`,
    [body, entryId],
  );
}

/** Remove a history entry. Cascades the attachment BLOB with it. */
export async function deleteEntry(entryId: number): Promise<void> {
  const conn = await db();
  await conn.execute(`DELETE FROM customer_history WHERE id = $1`, [entryId]);
}

/**
 * Append a history entry with an attached file (stored inline as a BLOB).
 * The Tauri command reads the file from disk and writes the row in one
 * round-trip — bytes don't cross the IPC boundary.
 */
export async function addEntryWithAttachment(
  customerUid: string,
  body: string,
  srcPath: string,
): Promise<{ id: number }> {
  const result = await invoke<{ id: number }>('add_history_entry_with_attachment', {
    customerUid,
    body,
    srcPath,
  });
  return result;
}

/**
 * Stream an attached BLOB out to a user-chosen path on disk. The
 * frontend should have already opened the save dialog and resolved an
 * absolute `targetPath`.
 */
export async function downloadAttachment(historyId: number, targetPath: string): Promise<void> {
  await invoke('download_history_attachment', { historyId, targetPath });
}
