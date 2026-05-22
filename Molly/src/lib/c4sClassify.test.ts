import { describe, it, expect } from 'vitest';
import { performersToPersonaCode, detectPersonaFromRows } from './c4sClassify';

describe('performersToPersonaCode', () => {
  it('maps CoC variants', () => {
    expect(performersToPersonaCode('CoC')).toBe('CoC');
    expect(performersToPersonaCode('coc')).toBe('CoC');
    expect(performersToPersonaCode(' COC ')).toBe('CoC');
    expect(performersToPersonaCode('Curse Of Curves')).toBe('CoC');
  });

  it('maps PoA variants', () => {
    expect(performersToPersonaCode('PrincessOFAddiction')).toBe('PoA');
    expect(performersToPersonaCode('princess of addiction')).toBe('PoA');
    expect(performersToPersonaCode('PoA')).toBe('PoA');
    expect(performersToPersonaCode('POA')).toBe('PoA');
  });

  it('returns null on empty / unknown', () => {
    expect(performersToPersonaCode('')).toBeNull();
    expect(performersToPersonaCode(undefined)).toBeNull();
    expect(performersToPersonaCode(null)).toBeNull();
    expect(performersToPersonaCode('Sheer Attraction')).toBeNull();
    expect(performersToPersonaCode('Sa')).toBeNull();
  });
});

describe('detectPersonaFromRows', () => {
  it('uses the first recognizable Performers value', () => {
    const rows = [
      { Performers: '', 'Clip ID': '1' },
      { Performers: 'CoC', 'Clip ID': '2' },
      { Performers: 'PrincessOFAddiction', 'Clip ID': '3' },
    ];
    expect(detectPersonaFromRows(rows)).toBe('CoC');
  });

  it('returns null when no row has a recognizable value', () => {
    const rows = [{ Performers: '', 'Clip ID': '1' }, { Performers: 'unknown', 'Clip ID': '2' }];
    expect(detectPersonaFromRows(rows)).toBeNull();
  });

  it('returns null on empty input', () => {
    expect(detectPersonaFromRows([])).toBeNull();
  });
});
