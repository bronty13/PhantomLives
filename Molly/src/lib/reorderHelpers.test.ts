import { describe, it, expect } from 'vitest';
import { reorderBeforeTarget } from './reorderHelpers';

const id = (n: number) => n;

describe('reorderBeforeTarget', () => {
  it('moves a later item earlier (drop before target)', () => {
    const out = reorderBeforeTarget([1, 2, 3, 4], id, 4, 2);
    expect(out).toEqual([1, 4, 2, 3]);
  });

  it('moves an earlier item later (drop before target, with shift compensation)', () => {
    const out = reorderBeforeTarget([1, 2, 3, 4], id, 1, 4);
    // src=1 (idx 0), dst=4 (idx 3). After remove, dst shifts to idx 2. Insert at 2 → [2,3,1,4]
    expect(out).toEqual([2, 3, 1, 4]);
  });

  it('no-op when src equals target', () => {
    const out = reorderBeforeTarget([1, 2, 3], id, 2, 2);
    expect(out).toEqual([1, 2, 3]);
  });

  it('no-op when src not in list', () => {
    const out = reorderBeforeTarget([1, 2, 3], id, 99, 2);
    expect(out).toEqual([1, 2, 3]);
  });

  it('no-op when target not in list', () => {
    const out = reorderBeforeTarget([1, 2, 3], id, 1, 99);
    expect(out).toEqual([1, 2, 3]);
  });

  it('handles object identifiers', () => {
    const items = [
      { id: 'a', n: 1 },
      { id: 'b', n: 2 },
      { id: 'c', n: 3 },
    ];
    const out = reorderBeforeTarget(items, (it) => it.id, 'c', 'a');
    expect(out.map((it) => it.id)).toEqual(['c', 'a', 'b']);
  });

  it('returns a new array (no mutation)', () => {
    const items = [1, 2, 3];
    const out = reorderBeforeTarget(items, id, 3, 1);
    expect(out).not.toBe(items);
    expect(items).toEqual([1, 2, 3]);
  });
});
