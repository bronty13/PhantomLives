import { describe, expect, it } from 'vitest';
import { compareVersions, isNewer } from '../src/shared/version';
import { unseenNotes, WHATS_NEW } from '../src/creator/data/whatsNew';
import { APP_VERSION } from '../src/shared/appMeta';

describe('compareVersions', () => {
  it('orders by numeric components, not lexically', () => {
    expect(compareVersions('0.3.10', '0.3.9')).toBe(1); // 10 > 9, not "1" < "9"
    expect(compareVersions('0.3.9', '0.3.10')).toBe(-1);
    expect(compareVersions('1.0.0', '0.9.9')).toBe(1);
  });

  it('treats missing trailing parts as zero', () => {
    expect(compareVersions('0.4', '0.4.0')).toBe(0);
    expect(compareVersions('0.4.1', '0.4')).toBe(1);
  });

  it('returns 0 for equal versions', () => {
    expect(compareVersions('0.4.0', '0.4.0')).toBe(0);
  });
});

describe('isNewer', () => {
  it('is true only when strictly newer', () => {
    expect(isNewer('0.4.1', '0.4.0')).toBe(true);
    expect(isNewer('0.4.0', '0.4.0')).toBe(false);
    expect(isNewer('0.3.9', '0.4.0')).toBe(false);
  });
});

describe('unseenNotes', () => {
  it('shows nothing on a brand-new install (no last-seen marker)', () => {
    expect(unseenNotes(null)).toEqual([]);
  });

  it('shows only notes strictly newer than last seen, newest first', () => {
    const notes = unseenNotes('0.0.0');
    expect(notes.length).toBe(WHATS_NEW.length);
    // sorted newest-first
    for (let i = 1; i < notes.length; i++) {
      expect(compareVersions(notes[i - 1].version, notes[i].version)).toBeGreaterThan(0);
    }
  });

  it('shows nothing once the current version has been seen', () => {
    expect(unseenNotes(APP_VERSION)).toEqual([]);
  });
});

describe('release metadata stays consistent', () => {
  it('has a What’s New entry matching the current APP_VERSION', () => {
    expect(WHATS_NEW.some((n) => n.version === APP_VERSION)).toBe(true);
  });
});
