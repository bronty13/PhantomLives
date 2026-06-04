import { useCallback, useEffect, useState } from 'react';

export type ThemePref = 'auto' | 'light' | 'dark';

const KEY = 'pm-theme';

function read(): ThemePref {
  const raw = (typeof localStorage !== 'undefined' && localStorage.getItem(KEY)) || 'auto';
  return raw === 'light' || raw === 'dark' ? raw : 'auto';
}

function apply(pref: ThemePref) {
  const dark =
    pref === 'dark' ||
    (pref === 'auto' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.classList.toggle('dark', dark);
}

/**
 * Manages the light/dark/auto preference. Mirrors the no-flash bootstrap in
 * index.html (same `pm-theme` key). Re-applies on OS scheme changes while in
 * `auto`.
 */
export function useUiTheme() {
  const [pref, setPref] = useState<ThemePref>(read);

  useEffect(() => {
    apply(pref);
    try {
      localStorage.setItem(KEY, pref);
    } catch {
      /* private mode — ignore */
    }
  }, [pref]);

  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (read() === 'auto') apply('auto');
    };
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  const cycle = useCallback(() => {
    setPref((p) => (p === 'auto' ? 'light' : p === 'light' ? 'dark' : 'auto'));
  }, []);

  return { pref, setPref, cycle };
}
