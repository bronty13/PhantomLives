import Database from '@tauri-apps/plugin-sql';

let dbPromise: Promise<Database> | null = null;

// Single shared SQLite handle. tauri-plugin-sql is happy with one
// connection per app and sharing keeps query state predictable.
export function db(): Promise<Database> {
  if (!dbPromise) dbPromise = Database.load('sqlite:sidemolly.db');
  return dbPromise;
}
