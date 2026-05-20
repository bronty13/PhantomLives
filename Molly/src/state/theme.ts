import { useEffect } from 'react';
import type { Persona } from './personas';

/**
 * Convert a "#RRGGBB" string to the "r g b" channel triple that our
 * Tailwind theme tokens expect (so `rgb(var(--persona-primary) / 0.5)`
 * works for alpha overlays).
 */
function hexToChannels(hex: string): string {
  const clean = hex.replace('#', '');
  const full =
    clean.length === 3
      ? clean
          .split('')
          .map((c) => c + c)
          .join('')
      : clean;
  const r = parseInt(full.slice(0, 2), 16);
  const g = parseInt(full.slice(2, 4), 16);
  const b = parseInt(full.slice(4, 6), 16);
  return `${r} ${g} ${b}`;
}

/**
 * Apply the active persona's colors as CSS custom properties on :root.
 * Every component that wants persona-aware coloring reads the variables
 * via `rgb(var(--persona-*) / <alpha>)` — switching persona swaps the
 * variable values and the whole UI recolors with a CSS transition.
 *
 * Mirrors `Timeliner/Sources/Timeliner/Models/Theme.swift` (preset themes
 * resolved at render time) but with runtime customizability per persona.
 */
export function useApplyPersonaTheme(active: Persona) {
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--persona-primary', hexToChannels(active.primaryColor));
    root.style.setProperty('--persona-secondary', hexToChannels(active.secondaryColor));
    root.style.setProperty('--persona-tint', hexToChannels(active.tintColor));
    root.style.setProperty('--persona-accent', hexToChannels(active.accentColor));
    root.style.setProperty('--persona-text', hexToChannels(active.textColor));
  }, [active]);
}
