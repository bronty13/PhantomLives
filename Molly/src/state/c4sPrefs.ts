import { useEffect, useState } from 'react';

// localStorage-backed user prefs for the C4S view. Persona + Title are
// always visible (no toggle) — every other column has an entry below with
// the appropriate default. Defaults track the data shape we observed in
// Sallie's real exports: Tracking Tag and Preview Filename are 0% filled
// across both files and so default OFF; sparse columns (Sales / Income)
// default ON because they're load-bearing when present.

export interface C4SColumnPrefs {
  clipId: boolean;
  clipStatus: boolean;
  categories: boolean;
  keywords: boolean;
  price: boolean;
  salesCount: boolean;
  income6mo: boolean;
  clipFilename: boolean;
  clipThumbnail: boolean;
  clipTrackingTag: boolean;
  clipPreview: boolean;
}

export interface C4SPrefs {
  showStaleBanner: boolean;
  columns: C4SColumnPrefs;
}

export const DEFAULT_C4S_PREFS: C4SPrefs = {
  showStaleBanner: true,
  columns: {
    clipId: true,
    clipStatus: true,
    categories: true,
    keywords: true,
    price: true,
    salesCount: true,
    income6mo: true,
    clipFilename: true,
    clipThumbnail: true,
    clipTrackingTag: false,
    clipPreview: false,
  },
};

const STORAGE_KEY = 'molly.c4s.prefs';

function readPrefs(): C4SPrefs {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_C4S_PREFS;
    const parsed = JSON.parse(raw) as Partial<C4SPrefs>;
    return {
      showStaleBanner: parsed.showStaleBanner ?? DEFAULT_C4S_PREFS.showStaleBanner,
      columns: { ...DEFAULT_C4S_PREFS.columns, ...(parsed.columns ?? {}) },
    };
  } catch {
    return DEFAULT_C4S_PREFS;
  }
}

function writePrefs(p: C4SPrefs): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(p));
  } catch {
    // localStorage can throw in private mode; just no-op.
  }
}

/**
 * Cross-tab / cross-component pref subscription. The hook reads on mount,
 * persists on every set, and listens for the storage event so two
 * windows of the same app (or Settings + the C4S view) stay in sync.
 */
export function useC4SPrefs(): [C4SPrefs, (next: Partial<C4SPrefs>) => void, (next: Partial<C4SColumnPrefs>) => void, () => void] {
  const [prefs, setPrefs] = useState<C4SPrefs>(() => readPrefs());

  useEffect(() => {
    const handler = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY) setPrefs(readPrefs());
    };
    window.addEventListener('storage', handler);
    return () => window.removeEventListener('storage', handler);
  }, []);

  const apply = (next: Partial<C4SPrefs>) => {
    const merged: C4SPrefs = {
      showStaleBanner: next.showStaleBanner ?? prefs.showStaleBanner,
      columns: { ...prefs.columns, ...(next.columns ?? {}) },
    };
    writePrefs(merged);
    setPrefs(merged);
  };
  const applyColumns = (next: Partial<C4SColumnPrefs>) =>
    apply({ columns: { ...prefs.columns, ...next } });
  const reset = () => {
    writePrefs(DEFAULT_C4S_PREFS);
    setPrefs(DEFAULT_C4S_PREFS);
  };

  return [prefs, apply, applyColumns, reset];
}
