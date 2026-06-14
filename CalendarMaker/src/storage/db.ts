// Persistence. Uses localStorage (with an in-memory fallback) — NOT IndexedDB,
// because Chromium browsers block/hang IndexedDB on `file://` opaque origins,
// which is exactly how this app is distributed (unzip → open index.html). All
// stored data is small (calendars/themes/settings/sayings are tiny JSON; the big
// Bible/fonts are compiled-in code constants), so localStorage is plenty.

import type { AppSettings, CalendarBundle, FillerEntry, Theme } from '../model/types';
import { DEFAULT_APP_SETTINGS } from '../model/types';
import { SEED_THEMES } from '../model/seedThemes';

const K = {
  bundles: 'cm.bundles',
  themes: 'cm.themes',
  sayings: 'cm.sayings',
  settings: 'cm.settings',
  seeded: 'cm.seeded',
  lastSeenVersion: 'cm.lastSeenVersion',
};

// --- low-level store (localStorage, falling back to in-memory) --------------

const mem = new Map<string, string>();
let useMem = false;

function rawGet(key: string): string | null {
  if (useMem) return mem.get(key) ?? null;
  try {
    return localStorage.getItem(key);
  } catch {
    useMem = true;
    return mem.get(key) ?? null;
  }
}

function rawSet(key: string, value: string): void {
  if (useMem) {
    mem.set(key, value);
    return;
  }
  try {
    localStorage.setItem(key, value);
  } catch {
    useMem = true;
    mem.set(key, value);
  }
}

function readMap<T>(key: string): Record<string, T> {
  const raw = rawGet(key);
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, T>;
  } catch {
    return {};
  }
}

function writeMap<T>(key: string, map: Record<string, T>): void {
  rawSet(key, JSON.stringify(map));
}

// --- seeding ---------------------------------------------------------------

/** Idempotent first-run seed of the built-in themes. */
export async function ensureSeeded(): Promise<void> {
  if (rawGet(K.seeded)) return;
  const themes = readMap<Theme>(K.themes);
  for (const t of SEED_THEMES) themes[t.id] = t;
  writeMap(K.themes, themes);
  rawSet(K.seeded, '1');
}

// --- Bundles ---------------------------------------------------------------

export async function listBundles(): Promise<CalendarBundle[]> {
  return Object.values(readMap<CalendarBundle>(K.bundles)).sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function getBundle(id: string): Promise<CalendarBundle | undefined> {
  return readMap<CalendarBundle>(K.bundles)[id];
}

export async function saveBundle(bundle: CalendarBundle): Promise<void> {
  const map = readMap<CalendarBundle>(K.bundles);
  map[bundle.id] = { ...bundle, updatedAt: Date.now() };
  writeMap(K.bundles, map);
}

export async function deleteBundle(id: string): Promise<void> {
  const map = readMap<CalendarBundle>(K.bundles);
  delete map[id];
  writeMap(K.bundles, map);
}

// --- Themes ----------------------------------------------------------------

export async function listThemes(): Promise<Theme[]> {
  return Object.values(readMap<Theme>(K.themes)).sort((a, b) => {
    if (a.builtin !== b.builtin) return a.builtin ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

export async function getTheme(id: string): Promise<Theme | undefined> {
  return readMap<Theme>(K.themes)[id];
}

export async function saveTheme(theme: Theme): Promise<void> {
  const map = readMap<Theme>(K.themes);
  map[theme.id] = theme;
  writeMap(K.themes, map);
}

export async function deleteTheme(id: string): Promise<void> {
  const map = readMap<Theme>(K.themes);
  delete map[id];
  writeMap(K.themes, map);
}

// --- Custom sayings --------------------------------------------------------

export async function listCustomSayings(): Promise<FillerEntry[]> {
  return Object.values(readMap<FillerEntry>(K.sayings));
}

export async function addCustomSaying(entry: FillerEntry): Promise<void> {
  const map = readMap<FillerEntry>(K.sayings);
  map[entry.id] = entry;
  writeMap(K.sayings, map);
}

export async function updateCustomSaying(entry: FillerEntry): Promise<void> {
  const map = readMap<FillerEntry>(K.sayings);
  map[entry.id] = entry;
  writeMap(K.sayings, map);
}

export async function deleteCustomSaying(id: string): Promise<void> {
  const map = readMap<FillerEntry>(K.sayings);
  delete map[id];
  writeMap(K.sayings, map);
}

// --- Settings --------------------------------------------------------------

export async function getSettings(): Promise<AppSettings> {
  const raw = rawGet(K.settings);
  if (!raw) return { ...DEFAULT_APP_SETTINGS };
  try {
    return { ...DEFAULT_APP_SETTINGS, ...(JSON.parse(raw) as Partial<AppSettings>) };
  } catch {
    return { ...DEFAULT_APP_SETTINGS };
  }
}

export async function saveSettings(settings: AppSettings): Promise<void> {
  rawSet(K.settings, JSON.stringify(settings));
}

// --- "What's New" bookkeeping -----------------------------------------------

/** The app version whose release notes the user last saw (null = never). */
export function getLastSeenVersion(): string | null {
  return rawGet(K.lastSeenVersion);
}

export function setLastSeenVersion(version: string): void {
  rawSet(K.lastSeenVersion, version);
}
