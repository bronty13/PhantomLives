import { useEffect, useState } from 'react';
import { db } from '../data/db';

// Phase 15 PR4: light / dark / system UI theme preference.
//
// Stored in app_settings under key 'ui.theme'. Default 'light' (seeded
// by migration 033). Applied by toggling a `dark` class on <html> —
// Tailwind config is set to `darkMode: 'class'` so existing `dark:*`
// utilities take effect.

export type ThemeMode = 'light' | 'dark' | 'system';

const SETTING_KEY = 'ui.theme';

export async function loadThemeMode(): Promise<ThemeMode> {
  try {
    const conn = await db();
    const rows = await conn.select<{ value: string }[]>(
      'SELECT value FROM app_settings WHERE key = $1',
      [SETTING_KEY],
    );
    const v = rows[0]?.value;
    if (v === 'dark' || v === 'system' || v === 'light') return v;
  } catch {
    // first-run / DB not ready yet — fall through to default
  }
  return 'light';
}

export async function saveThemeMode(mode: ThemeMode): Promise<void> {
  const conn = await db();
  await conn.execute(
    'INSERT INTO app_settings (key, value) VALUES ($1, $2) ON CONFLICT(key) DO UPDATE SET value = $2',
    [SETTING_KEY, mode],
  );
}

/** Resolve the effective theme for "system" by consulting the media query. */
function resolveEffective(mode: ThemeMode): 'light' | 'dark' {
  if (mode === 'light' || mode === 'dark') return mode;
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'light';
}

function applyEffective(effective: 'light' | 'dark') {
  const html = document.documentElement;
  if (effective === 'dark') {
    html.classList.add('dark');
    html.style.colorScheme = 'dark';
  } else {
    html.classList.remove('dark');
    html.style.colorScheme = 'light';
  }
}

/** Hook for the App root. Loads the saved preference once, applies it,
 *  and re-applies whenever the OS preference flips while mode='system'. */
export function useUiTheme() {
  const [mode, setModeState] = useState<ThemeMode>('light');

  useEffect(() => {
    let alive = true;
    loadThemeMode().then((m) => {
      if (!alive) return;
      setModeState(m);
      applyEffective(resolveEffective(m));
    });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    applyEffective(resolveEffective(mode));
    if (mode !== 'system' || typeof window === 'undefined' || !window.matchMedia) {
      return;
    }
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => applyEffective(resolveEffective('system'));
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [mode]);

  async function setMode(next: ThemeMode) {
    setModeState(next);
    applyEffective(resolveEffective(next));
    try {
      await saveThemeMode(next);
    } catch (e) {
      console.warn('Could not persist theme preference', e);
    }
  }

  return { mode, setMode };
}
