import { describe, it, expect } from 'vitest';
import { compareVersions, isNewer } from '../src/update/version';
import { unseenNotes, WHATS_NEW } from '../src/data/whatsNew';

describe('version comparison', () => {
  it('orders dotted versions numerically (not lexically)', () => {
    expect(compareVersions('0.3.10', '0.3.9')).toBe(1); // 10 > 9, not "10" < "9"
    expect(compareVersions('0.3.4', '0.3.4')).toBe(0);
    expect(compareVersions('0.10.0', '0.9.9')).toBe(1);
    expect(compareVersions('1.0.0', '0.99.99')).toBe(1);
  });

  it('treats missing trailing parts as zero', () => {
    expect(compareVersions('0.3', '0.3.0')).toBe(0);
    expect(compareVersions('0.3.1', '0.3')).toBe(1);
  });

  it('isNewer is strict', () => {
    expect(isNewer('0.3.5', '0.3.4')).toBe(true);
    expect(isNewer('0.3.4', '0.3.4')).toBe(false);
    expect(isNewer('0.3.3', '0.3.4')).toBe(false);
  });
});

describe('unseenNotes', () => {
  it('shows nothing on a first run (no last-seen version)', () => {
    expect(unseenNotes(null)).toEqual([]);
  });

  it('shows only notes strictly newer than the last-seen version, newest first', () => {
    const latest = WHATS_NEW.map((n) => n.version).sort((a, b) => compareVersions(b, a))[0];
    // Pretend the user last saw a very old version → the latest note is surfaced.
    const notes = unseenNotes('0.0.1');
    expect(notes.length).toBeGreaterThan(0);
    expect(notes[0].version).toBe(latest);
    // Already on the latest → nothing new.
    expect(unseenNotes(latest)).toEqual([]);
  });

  it('every release note has a version, date, and at least one highlight', () => {
    for (const n of WHATS_NEW) {
      expect(n.version).toMatch(/^\d+\.\d+/);
      expect(n.date.length).toBeGreaterThan(0);
      expect(n.highlights.length).toBeGreaterThan(0);
    }
  });
});
