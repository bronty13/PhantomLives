import { describe, it, expect } from 'vitest';
import { expandTokens, filterByPlatform } from '../../src/main/cache/tokens';
import type { CachePreset } from '../../src/shared/types';

describe('expandTokens', () => {
  const env = { HOME: '/Users/me', LOCALAPPDATA: 'C:\\Users\\me\\AppData\\Local', TMPDIR: '/tmp' };
  it('expands known tokens', () => {
    expect(expandTokens('${HOME}/Library/Caches', env)).toBe('/Users/me/Library/Caches');
    expect(expandTokens('${LOCALAPPDATA}\\Temp', env)).toBe('C:\\Users\\me\\AppData\\Local\\Temp');
  });
  it('leaves unknown tokens intact', () => {
    expect(expandTokens('${NOPE}/x', env)).toBe('${NOPE}/x');
  });
  it('handles multiple tokens', () => {
    expect(expandTokens('${HOME}/${TMPDIR}', env)).toBe('/Users/me//tmp');
  });
});

describe('filterByPlatform', () => {
  const presets: CachePreset[] = [
    { id: 'm', label: '', description: '', platform: 'darwin', riskLevel: 'low', paths: [] },
    { id: 'w', label: '', description: '', platform: 'win32', riskLevel: 'low', paths: [] },
    { id: 'a', label: '', description: '', platform: 'all', riskLevel: 'low', paths: [] }
  ];
  it('keeps platform + all', () => {
    expect(filterByPlatform(presets, 'darwin').map((p) => p.id)).toEqual(['m', 'a']);
    expect(filterByPlatform(presets, 'win32').map((p) => p.id)).toEqual(['w', 'a']);
  });
});
