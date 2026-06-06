import { describe, expect, it } from 'vitest';
import { generateWheelResult, wheelResultBlob } from '../src/shared/wheelResult';

const colors = { primary: '#5b2a86', accent: '#d98324', text: '#1a1a1a' };

describe('wheel result PDF', () => {
  it('builds a non-empty blob for a single result', () => {
    const blob = wheelResultBlob({
      wheelName: 'Prize Wheel',
      results: [{ label: 'Free Coffee', at: '2026-06-06 10:00' }],
      colors,
    });
    expect(blob.size).toBeGreaterThan(0);
  });

  it('renders a history when given multiple results', () => {
    const results = Array.from({ length: 12 }, (_, i) => ({
      label: `Prize ${i + 1}`,
      at: `2026-06-06 10:${String(i).padStart(2, '0')}`,
    }));
    const doc = generateWheelResult({ wheelName: 'Big Wheel', results, colors });
    expect(doc.output('blob').size).toBeGreaterThan(0);
  });

  it('tolerates bad colors and empty / missing labels', () => {
    const blob = wheelResultBlob({
      wheelName: '',
      results: [{ label: '', at: '' }],
      colors: { primary: 'nope', accent: '', text: '#zzz' },
    });
    expect(blob.size).toBeGreaterThan(0);
  });

  it('does not throw on an empty results list', () => {
    expect(() => wheelResultBlob({ wheelName: 'Empty', results: [], colors })).not.toThrow();
  });
});
