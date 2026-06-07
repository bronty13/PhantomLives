import { describe, it, expect } from 'vitest';
import { greeting } from '../src/app/util';
import { sayingPool, getRandomSaying, rerollSaying, SAYINGS } from '../src/data/sayings';
import type { FillerEntry } from '../src/model/types';

describe('greeting', () => {
  const at = (h: number) => new Date(2026, 5, 1, h, 0, 0);
  it('varies by time of day and uses the name', () => {
    expect(greeting('Jan', at(8))).toBe('Good morning, Jan');
    expect(greeting('Jan', at(13))).toBe('Good afternoon, Jan');
    expect(greeting('Jan', at(19))).toBe('Good evening, Jan');
    expect(greeting('Jan', at(23))).toBe('Good night, Jan');
  });
  it('falls back to "friend" when the name is blank', () => {
    expect(greeting('   ', at(8))).toBe('Good morning, friend');
  });
});

describe('sayings pool', () => {
  const custom: FillerEntry[] = [
    { id: 'c1', kind: 'saying', text: 'Custom one', reference: 'Jan' },
    { id: 'c2', kind: 'saying', text: 'Custom two' },
  ];

  it('combines seeded + custom sayings', () => {
    const pool = sayingPool(custom);
    expect(pool.length).toBe(SAYINGS.length + 2);
    expect(pool.some((s) => s.id === 'c1')).toBe(true);
  });

  it('getRandomSaying draws from the provided pool', () => {
    const only = [custom[0]];
    expect(getRandomSaying(only).id).toBe('c1');
  });

  it('rerollSaying avoids the excluded id when possible', () => {
    const r = rerollSaying(custom, 'c1');
    expect(r.id).toBe('c2');
  });

  it('handles an empty pool gracefully', () => {
    expect(getRandomSaying([]).text).toBe('');
  });
});
