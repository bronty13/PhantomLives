import { useEffect, useState } from 'react';
import { db } from '../data/db';

// Per-feature on/off toggles. Each flag is one row in `app_settings`
// keyed `feature.<name>` with value `'1'` (on) or `'0'` (off). Default
// is whatever the loader hard-codes when the row is absent — there is
// deliberately no migration seeding values, so flipping a default in
// code automatically takes effect for users who have never touched the
// toggle (and never changes anything for users who have).

const PROMOS_KEY = 'feature.promosEnabled';
const PROMOS_DEFAULT = false;

async function loadBoolFlag(key: string, fallback: boolean): Promise<boolean> {
  try {
    const conn = await db();
    const rows = await conn.select<{ value: string }[]>(
      'SELECT value FROM app_settings WHERE key = $1',
      [key],
    );
    const v = rows[0]?.value;
    if (v === '1') return true;
    if (v === '0') return false;
  } catch {
    // first-run / DB not ready yet — fall through to default
  }
  return fallback;
}

async function saveBoolFlag(key: string, value: boolean): Promise<void> {
  const conn = await db();
  await conn.execute(
    'INSERT INTO app_settings (key, value) VALUES ($1, $2) ON CONFLICT(key) DO UPDATE SET value = $2',
    [key, value ? '1' : '0'],
  );
}

export async function loadPromosEnabled(): Promise<boolean> {
  return loadBoolFlag(PROMOS_KEY, PROMOS_DEFAULT);
}

export async function savePromosEnabled(value: boolean): Promise<void> {
  return saveBoolFlag(PROMOS_KEY, value);
}

/**
 * Hook for the Promos feature flag. `loaded` lets callers wait one tick
 * before reacting to the flag — without it, the sidebar would flash the
 * Promos entry for a frame on every launch when the flag is off.
 */
export function usePromosEnabled() {
  const [enabled, setEnabledState] = useState<boolean>(PROMOS_DEFAULT);
  const [loaded, setLoaded] = useState<boolean>(false);

  useEffect(() => {
    let alive = true;
    loadPromosEnabled().then((v) => {
      if (!alive) return;
      setEnabledState(v);
      setLoaded(true);
    });
    return () => { alive = false; };
  }, []);

  async function setEnabled(next: boolean) {
    setEnabledState(next);
    try {
      await savePromosEnabled(next);
    } catch (e) {
      console.warn('Could not persist promosEnabled flag', e);
    }
  }

  return { enabled, setEnabled, loaded };
}
