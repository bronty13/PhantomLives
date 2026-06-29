import { describe, it, expect } from 'vitest';
import { formatBytes, savingsPercent } from './fileSize';

describe('formatBytes', () => {
  it('formats across units with decimal (1000-based) steps', () => {
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(500)).toBe('500 B');
    expect(formatBytes(12_300)).toBe('12.3 KB');
    expect(formatBytes(880_000_000)).toBe('880 MB');
    expect(formatBytes(4_200_000_000)).toBe('4.2 GB');
    expect(formatBytes(1_000_000_000)).toBe('1.0 GB');
  });

  it('guards against bad input', () => {
    expect(formatBytes(-1)).toBe('—');
    expect(formatBytes(NaN)).toBe('—');
  });
});

describe('savingsPercent', () => {
  it('reports how much smaller the output is', () => {
    expect(savingsPercent(4_200_000_000, 880_000_000)).toBe(79);
    expect(savingsPercent(1000, 250)).toBe(75);
  });

  it('clamps to 0 for non-positive input or a bigger output', () => {
    expect(savingsPercent(0, 0)).toBe(0);
    expect(savingsPercent(100, 150)).toBe(0);
  });
});
