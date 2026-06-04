import { db } from './db';

interface KV {
  value: string;
}

export async function getSetting(key: string): Promise<string> {
  const d = await db();
  const rows = await d.select<KV[]>('SELECT value FROM app_settings WHERE key = ?', [
    key,
  ]);
  return rows[0]?.value ?? '';
}

export async function setSetting(key: string, value: string): Promise<void> {
  const d = await db();
  await d.execute(
    `INSERT INTO app_settings (key, value) VALUES (?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    [key, value],
  );
}

/** Export directory override; empty string = default ~/Downloads/PurpleMind/. */
export const getExportDir = () => getSetting('export_dir');
export const setExportDir = (path: string) => setSetting('export_dir', path);
