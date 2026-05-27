import { describe, expect, it } from 'vitest';
import { DEFAULT_THEME, normalizeTheme, resolveDark } from './theme';

describe('theme', () => {
  it('defaults to dark', () => {
    expect(DEFAULT_THEME).toBe('dark');
  });

  it('normalizeTheme coerces unknown values to the default', () => {
    expect(normalizeTheme('dark')).toBe('dark');
    expect(normalizeTheme('light')).toBe('light');
    expect(normalizeTheme('auto')).toBe('auto');
    expect(normalizeTheme(null)).toBe('dark');
    expect(normalizeTheme(undefined)).toBe('dark');
    expect(normalizeTheme('nonsense')).toBe('dark');
    expect(normalizeTheme('')).toBe('dark');
  });

  it('resolveDark honors explicit modes regardless of system', () => {
    expect(resolveDark('dark', false)).toBe(true);
    expect(resolveDark('dark', true)).toBe(true);
    expect(resolveDark('light', true)).toBe(false);
    expect(resolveDark('light', false)).toBe(false);
  });

  it('resolveDark follows the system preference in auto', () => {
    expect(resolveDark('auto', true)).toBe(true);
    expect(resolveDark('auto', false)).toBe(false);
  });
});
