import { useEffect, useState } from 'react';
import { db } from '../data/db';
import {
  type RotationMode,
  ROTATION_MODE_DEFAULT,
  REST_DAYS_DEFAULT,
  clampRestDays,
} from '../lib/rotationRule';

// Subreddit rotation-reset preferences. Two rows in `app_settings`:
//   reddit.rotation.mode     'auto' | 'manual'   (default 'auto')
//   reddit.rotation.restDays integer string      (default '2')
//
// Same lazy, migration-free convention as featureFlags / incomeGoals: rows
// are written on first change, and the hard-coded defaults apply until then —
// so changing a default in code reaches anyone who's never touched the
// setting, and never overrides someone who has.

const MODE_KEY = 'reddit.rotation.mode';
const REST_DAYS_KEY = 'reddit.rotation.restDays';

export interface RotationSettings {
  mode: RotationMode;
  restDays: number;
}

async function readSetting(key: string): Promise<string | undefined> {
  const conn = await db();
  const rows = await conn.select<{ value: string }[]>(
    'SELECT value FROM app_settings WHERE key = $1',
    [key],
  );
  return rows[0]?.value;
}

async function writeSetting(key: string, value: string): Promise<void> {
  const conn = await db();
  await conn.execute(
    'INSERT INTO app_settings (key, value) VALUES ($1, $2) ON CONFLICT(key) DO UPDATE SET value = $2',
    [key, value],
  );
}

export async function loadRotationSettings(): Promise<RotationSettings> {
  try {
    const [modeRaw, restRaw] = await Promise.all([
      readSetting(MODE_KEY),
      readSetting(REST_DAYS_KEY),
    ]);
    const mode: RotationMode = modeRaw === 'manual' ? 'manual' : ROTATION_MODE_DEFAULT;
    const restDays = restRaw != null ? clampRestDays(parseInt(restRaw, 10)) : REST_DAYS_DEFAULT;
    return { mode, restDays };
  } catch {
    // first-run / DB not ready yet — fall through to defaults
    return { mode: ROTATION_MODE_DEFAULT, restDays: REST_DAYS_DEFAULT };
  }
}

export async function saveRotationMode(mode: RotationMode): Promise<void> {
  await writeSetting(MODE_KEY, mode);
}

export async function saveRotationRestDays(days: number): Promise<void> {
  await writeSetting(REST_DAYS_KEY, String(clampRestDays(days)));
}

/**
 * Hook for the rotation settings. `loaded` lets the tracker hold off on
 * deriving badges until the saved mode/restDays arrive, so a Resting sub
 * doesn't flash "Ready" for a frame on launch.
 */
export function useRotationSettings() {
  const [settings, setSettings] = useState<RotationSettings>({
    mode: ROTATION_MODE_DEFAULT,
    restDays: REST_DAYS_DEFAULT,
  });
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let alive = true;
    loadRotationSettings().then((s) => {
      if (!alive) return;
      setSettings(s);
      setLoaded(true);
    });
    return () => { alive = false; };
  }, []);

  async function setMode(mode: RotationMode) {
    setSettings((cur) => ({ ...cur, mode }));
    try { await saveRotationMode(mode); }
    catch (e) { console.warn('Could not persist rotation mode', e); }
  }

  async function setRestDays(days: number) {
    const clamped = clampRestDays(days);
    setSettings((cur) => ({ ...cur, restDays: clamped }));
    try { await saveRotationRestDays(clamped); }
    catch (e) { console.warn('Could not persist rotation rest days', e); }
  }

  return { ...settings, setMode, setRestDays, loaded };
}
