// Appearance / theme handling.
//
// Three modes: 'dark' (default), 'light', and 'auto' (follow the OS
// `prefers-color-scheme`). The choice persists in localStorage and is
// applied by toggling the `dark` class on <html> — the CSS in
// styles/index.css keys all surface vars off `html.dark`.
//
// To avoid a light-mode flash on launch, index.html runs an inline
// bootstrap that applies the same logic *before* React mounts. Keep the
// KEY + DEFAULT_THEME below in sync with that inline script.

export type Theme = 'dark' | 'light' | 'auto';

export const THEME_KEY = 'sm-theme';
export const DEFAULT_THEME: Theme = 'dark';

/** Coerce a stored/raw value to a valid Theme (default dark). Pure. */
export function normalizeTheme(value: string | null | undefined): Theme {
  return value === 'light' || value === 'auto' || value === 'dark'
    ? value
    : DEFAULT_THEME;
}

/** Whether the `dark` class should be applied. Pure — pass the system
 *  preference explicitly so this is testable without a DOM. */
export function resolveDark(theme: Theme, systemPrefersDark: boolean): boolean {
  if (theme === 'auto') return systemPrefersDark;
  return theme === 'dark';
}

function systemPrefersDark(): boolean {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

/** Current persisted theme (default dark; never throws). */
export function getTheme(): Theme {
  try { return normalizeTheme(localStorage.getItem(THEME_KEY)); }
  catch { return DEFAULT_THEME; }
}

/** Apply a theme to the document now. */
export function applyTheme(theme: Theme): void {
  document.documentElement.classList.toggle('dark', resolveDark(theme, systemPrefersDark()));
}

/** Persist + apply. */
export function setTheme(theme: Theme): void {
  try { localStorage.setItem(THEME_KEY, theme); } catch { /* private mode / quota — apply anyway */ }
  applyTheme(theme);
}

/** Re-apply when the OS appearance flips, but only while in 'auto'.
 *  Returns an unsubscribe fn. No-op outside a browser. */
export function watchSystemTheme(): () => void {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return () => {};
  }
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  const handler = () => { if (getTheme() === 'auto') applyTheme('auto'); };
  mq.addEventListener('change', handler);
  return () => mq.removeEventListener('change', handler);
}
