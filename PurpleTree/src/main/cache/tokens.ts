/**
 * @file tokens.ts — pure helpers for cache-preset path templating.
 *
 * Split out from presets.ts (which imports electron) so these can be unit
 * tested without pulling in the Electron runtime.
 */
import type { CachePreset } from '../../shared/types';

export type TokenEnv = Record<string, string>;

/** Expand ${TOKEN} occurrences in a template path. */
export function expandTokens(template: string, env: TokenEnv): string {
  return template.replace(/\$\{([A-Z_]+)\}/g, (_m, key: string) => env[key] ?? `\${${key}}`);
}

/** Keep presets that apply to a platform ('all' always applies). */
export function filterByPlatform(presets: CachePreset[], platform: NodeJS.Platform): CachePreset[] {
  return presets.filter((p) => p.platform === 'all' || p.platform === platform);
}
