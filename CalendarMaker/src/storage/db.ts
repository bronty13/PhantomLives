// Persistence: IndexedDB for saved calendar bundles + user themes, with app
// settings in a meta store. Built-in themes are seeded on first run so the Theme
// Manager lists everything uniformly. (Bible / sayings / holidays / fonts are
// static code data, not stored here.)

import { openDB, type IDBPDatabase } from 'idb';
import type { AppSettings, CalendarBundle, Theme } from '../model/types';
import { DEFAULT_APP_SETTINGS } from '../model/types';
import { SEED_THEMES } from '../model/seedThemes';

const DB_NAME = 'calendarmaker';
const DB_VERSION = 1;
const SETTINGS_KEY = 'app-settings';
const SEEDED_KEY = 'seeded';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(database) {
        if (!database.objectStoreNames.contains('bundles')) {
          database.createObjectStore('bundles', { keyPath: 'id' });
        }
        if (!database.objectStoreNames.contains('themes')) {
          database.createObjectStore('themes', { keyPath: 'id' });
        }
        if (!database.objectStoreNames.contains('meta')) {
          database.createObjectStore('meta');
        }
      },
    });
  }
  return dbPromise;
}

/** Idempotent first-run seed of the built-in themes. */
export async function ensureSeeded(): Promise<void> {
  const d = await db();
  const seeded = await d.get('meta', SEEDED_KEY);
  if (seeded) return;
  const tx = d.transaction('themes', 'readwrite');
  for (const theme of SEED_THEMES) await tx.store.put(theme);
  await tx.done;
  await d.put('meta', true, SEEDED_KEY);
}

// --- Bundles ---------------------------------------------------------------

export async function listBundles(): Promise<CalendarBundle[]> {
  const all = (await (await db()).getAll('bundles')) as CalendarBundle[];
  return all.sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function getBundle(id: string): Promise<CalendarBundle | undefined> {
  return (await (await db()).get('bundles', id)) as CalendarBundle | undefined;
}

export async function saveBundle(bundle: CalendarBundle): Promise<void> {
  await (await db()).put('bundles', { ...bundle, updatedAt: Date.now() });
}

export async function deleteBundle(id: string): Promise<void> {
  await (await db()).delete('bundles', id);
}

// --- Themes ----------------------------------------------------------------

export async function listThemes(): Promise<Theme[]> {
  const all = (await (await db()).getAll('themes')) as Theme[];
  // Built-ins first (seed order), then user themes by name.
  return all.sort((a, b) => {
    if (a.builtin !== b.builtin) return a.builtin ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

export async function getTheme(id: string): Promise<Theme | undefined> {
  return (await (await db()).get('themes', id)) as Theme | undefined;
}

export async function saveTheme(theme: Theme): Promise<void> {
  await (await db()).put('themes', theme);
}

export async function deleteTheme(id: string): Promise<void> {
  await (await db()).delete('themes', id);
}

// --- Settings --------------------------------------------------------------

export async function getSettings(): Promise<AppSettings> {
  const stored = (await (await db()).get('meta', SETTINGS_KEY)) as AppSettings | undefined;
  return { ...DEFAULT_APP_SETTINGS, ...stored };
}

export async function saveSettings(settings: AppSettings): Promise<void> {
  await (await db()).put('meta', settings, SETTINGS_KEY);
}
