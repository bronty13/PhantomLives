import Database from '@tauri-apps/plugin-sql';

let dbPromise: Promise<Database> | null = null;

/**
 * Shared SQLite handle. tauri-plugin-sql runs the migrations registered in
 * src-tauri/src/lib.rs the first time the DB is loaded.
 */
export function db(): Promise<Database> {
  if (!dbPromise) dbPromise = Database.load('sqlite:purplemind.db');
  return dbPromise;
}

/** ISO-8601 timestamp used for created_at / updated_at columns. */
export function nowIso(): string {
  return new Date().toISOString();
}

/** RFC-4122 v4 id; crypto.randomUUID is available in the Tauri webview. */
export function newId(): string {
  return crypto.randomUUID();
}
