import { describe, expect, it } from 'vitest';
import { describeUnreadable, type DurationTotal } from './durationProbe';

const t = (p: Partial<DurationTotal>): DurationTotal => ({
  totalSeconds: 0,
  videoCount: 0,
  failedCount: 0,
  emptyCount: 0,
  ...p,
});

describe('describeUnreadable', () => {
  it('returns null when every video read fine', () => {
    expect(describeUnreadable(t({ videoCount: 3, totalSeconds: 120 }))).toBeNull();
  });

  it('calls out empty (0-byte) videos distinctly', () => {
    const msg = describeUnreadable(t({ videoCount: 5, failedCount: 5, emptyCount: 5 }));
    expect(msg).toBe('5 of 5 videos left out of the estimate — 5 are empty (0 bytes).');
  });

  it('uses singular phrasing for one empty video', () => {
    const msg = describeUnreadable(t({ videoCount: 1, failedCount: 1, emptyCount: 1 }));
    expect(msg).toBe('1 of 1 video left out of the estimate — 1 is empty (0 bytes).');
  });

  it('separates empty from otherwise-unreadable videos', () => {
    const msg = describeUnreadable(t({ videoCount: 4, failedCount: 3, emptyCount: 1 }));
    expect(msg).toBe('3 of 4 videos left out of the estimate — 1 is empty (0 bytes), 2 couldn’t be read.');
  });

  it('reports plain unreadable when none are empty', () => {
    const msg = describeUnreadable(t({ videoCount: 2, failedCount: 2, emptyCount: 0 }));
    expect(msg).toBe('2 of 2 videos left out of the estimate — 2 couldn’t be read.');
  });
});
