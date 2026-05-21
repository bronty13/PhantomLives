import { describe, it, expect } from 'vitest';
import {
  projectPageOrder,
  projectPageOrderDetailed
} from '../../src/renderer/src/features/viewer/projectOrder';
import type { PageOp } from '../../src/renderer/src/features/annotate/flatten';

describe('projectPageOrderDetailed', () => {
  it('identity when no ops', () => {
    const result = projectPageOrderDetailed([], 3);
    expect(result.map((s) => s.source)).toEqual([0, 1, 2]);
    expect(result.every((s) => s.rotation === 0)).toBe(true);
  });

  it('rotate accumulates and normalizes mod 360', () => {
    const ops: PageOp[] = [
      { kind: 'rotate', page: 1, degrees: 90 },
      { kind: 'rotate', page: 1, degrees: 270 }
    ];
    const r = projectPageOrderDetailed(ops, 3);
    expect(r[1].rotation).toBe(0);
  });

  it('rotate applies to all duplicates of the same source', () => {
    const ops: PageOp[] = [
      { kind: 'duplicate', page: 1 },
      { kind: 'rotate', page: 1, degrees: 90 }
    ];
    const r = projectPageOrderDetailed(ops, 2);
    expect(r.map((s) => s.source)).toEqual([0, 1, 1]);
    expect(r[1].rotation).toBe(90);
    expect(r[2].rotation).toBe(90);
  });

  it('crop preserves source identity and applies to all duplicates', () => {
    const ops: PageOp[] = [
      { kind: 'duplicate', page: 0 },
      { kind: 'crop', page: 0, crop: { x: 1, y: 2, width: 3, height: 4 } }
    ];
    const r = projectPageOrderDetailed(ops, 2);
    expect(r[0].crop).toEqual({ x: 1, y: 2, width: 3, height: 4 });
    expect(r[1].crop).toEqual({ x: 1, y: 2, width: 3, height: 4 });
    // duplicate's crop object is a separate copy
    expect(r[0].crop).not.toBe(r[1].crop);
  });

  it('delete removes the slot for that source', () => {
    const r = projectPageOrderDetailed([{ kind: 'delete', page: 1 }], 3);
    expect(r.map((s) => s.source)).toEqual([0, 2]);
  });

  it('insert-blank inserts a null-source slot after the target', () => {
    const r = projectPageOrderDetailed([{ kind: 'insert-blank', page: 0 }], 2);
    expect(r.map((s) => s.source)).toEqual([0, null, 1]);
  });

  it('duplicate preserves the source idx', () => {
    const r = projectPageOrderDetailed([{ kind: 'duplicate', page: 0 }], 2);
    expect(r.map((s) => s.source)).toEqual([0, 0, 1]);
  });

  it('move relocates the first occurrence of the source', () => {
    const r = projectPageOrderDetailed([{ kind: 'move', page: 0, to: 2 }], 3);
    expect(r.map((s) => s.source)).toEqual([1, 0, 2]);
  });

  it('move is a no-op when the target equals the current position', () => {
    const r = projectPageOrderDetailed([{ kind: 'move', page: 1, to: 1 }], 3);
    expect(r.map((s) => s.source)).toEqual([0, 1, 2]);
  });

  it('combined sequence: duplicate then move then delete', () => {
    const ops: PageOp[] = [
      { kind: 'duplicate', page: 0 }, // [0, 0, 1, 2]
      { kind: 'delete', page: 2 }, // [0, 0, 1]
      { kind: 'move', page: 1, to: 0 } // [1, 0, 0]
    ];
    const r = projectPageOrderDetailed(ops, 3);
    expect(r.map((s) => s.source)).toEqual([1, 0, 0]);
  });

  it('ops referencing a deleted source are no-ops', () => {
    const r = projectPageOrderDetailed(
      [
        { kind: 'delete', page: 1 },
        { kind: 'rotate', page: 1, degrees: 90 },
        { kind: 'duplicate', page: 1 }
      ],
      3
    );
    expect(r.map((s) => s.source)).toEqual([0, 2]);
  });
});

describe('projectPageOrder (legacy)', () => {
  it('returns -1 for blank slots and source idx otherwise', () => {
    const order = projectPageOrder(
      [
        { kind: 'duplicate', page: 0 },
        { kind: 'insert-blank', page: 1 }
      ],
      2
    );
    expect(order).toEqual([0, 0, 1, -1]);
  });
});
