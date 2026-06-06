// Creator persistence: IndexedDB (handles large base64 assets that would blow the
// ~5 MB localStorage cap) for quizzes + brandings, with global settings in a meta store.

import { openDB, type IDBPDatabase } from 'idb';
import type { Branding, GlobalSettings, Quiz } from '../../shared/model';
import { DEFAULT_GLOBAL_SETTINGS } from '../../shared/model';

const DB_NAME = 'quizzer';
const DB_VERSION = 1;
const SETTINGS_KEY = 'global-settings';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(database) {
        if (!database.objectStoreNames.contains('quizzes')) {
          database.createObjectStore('quizzes', { keyPath: 'id' });
        }
        if (!database.objectStoreNames.contains('brandings')) {
          database.createObjectStore('brandings', { keyPath: 'id' });
        }
        if (!database.objectStoreNames.contains('meta')) {
          database.createObjectStore('meta');
        }
      },
    });
  }
  return dbPromise;
}

// --- Quizzes ---------------------------------------------------------------

export async function listQuizzes(): Promise<Quiz[]> {
  const all = (await (await db()).getAll('quizzes')) as Quiz[];
  return all.sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function getQuiz(id: string): Promise<Quiz | undefined> {
  return (await (await db()).get('quizzes', id)) as Quiz | undefined;
}

export async function saveQuiz(quiz: Quiz): Promise<void> {
  await (await db()).put('quizzes', { ...quiz, updatedAt: Date.now() });
}

export async function deleteQuiz(id: string): Promise<void> {
  await (await db()).delete('quizzes', id);
}

// --- Brandings -------------------------------------------------------------

export async function listBrandings(): Promise<Branding[]> {
  const all = (await (await db()).getAll('brandings')) as Branding[];
  return all.sort((a, b) => a.name.localeCompare(b.name));
}

export async function getBranding(id: string): Promise<Branding | undefined> {
  return (await (await db()).get('brandings', id)) as Branding | undefined;
}

export async function saveBranding(branding: Branding): Promise<void> {
  await (await db()).put('brandings', { ...branding, updatedAt: Date.now() });
}

export async function deleteBranding(id: string): Promise<void> {
  await (await db()).delete('brandings', id);
}

// --- Settings --------------------------------------------------------------

export async function getSettings(): Promise<GlobalSettings> {
  const stored = (await (await db()).get('meta', SETTINGS_KEY)) as GlobalSettings | undefined;
  return { ...DEFAULT_GLOBAL_SETTINGS, ...stored };
}

export async function saveSettings(settings: GlobalSettings): Promise<void> {
  await (await db()).put('meta', settings, SETTINGS_KEY);
}
