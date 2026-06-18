import { describe, it, expect } from 'vitest';
import { cssFontSizeToNFSize, ptToSize, clampSize } from '../src/shared/fontSize';
import { classifyCount } from '../src/shared/validate/charCount';
import { compareVersions, isNewer } from '../src/shared/update/version';
import { unseenNotes, WHATS_NEW } from '../src/shared/whatsNew';
import { buildSanitizeReport, sanitizeNf } from '../src/shared/sanitize';

describe('font-size snapping', () => {
  it('snaps arbitrary pt to the nearest NiteFlirt rung', () => {
    expect(ptToSize(18)).toBe(5);
    expect(ptToSize(18.5)).toBe(5);
    expect(ptToSize(13)).toBe(3); // 12 closer than 14? both 1 away -> first wins (12=size3)
    expect(cssFontSizeToNFSize('24pt')).toBe(6);
    expect(cssFontSizeToNFSize('36pt')).toBe(7);
  });
  it('converts px to pt before snapping', () => {
    expect(cssFontSizeToNFSize('24px')).toBe(5); // 24px = 18pt = size 5
  });
  it('clamps out-of-range sizes', () => {
    expect(clampSize(0)).toBe(1);
    expect(clampSize(99)).toBe(7);
  });
});

describe('char-count classification', () => {
  it('flags over-limit for the right doc type', () => {
    expect(classifyCount(6000, 'profile').level).toBe('ok');
    expect(classifyCount(6700, 'profile').level).toBe('warn');
    expect(classifyCount(7100, 'profile').level).toBe('over');
    expect(classifyCount(7100, 'listing').level).toBe('ok'); // listing limit is 14000
  });
});

describe('version compare + whats-new', () => {
  it('orders dotted versions numerically', () => {
    expect(compareVersions('0.1.10', '0.1.9')).toBe(1);
    expect(isNewer('0.2.0', '0.1.9')).toBe(true);
    expect(isNewer('0.1.0', '0.1.0')).toBe(false);
  });
  it('shows nothing on first run, all notes have content', () => {
    expect(unseenNotes(null)).toEqual([]);
    for (const n of WHATS_NEW) {
      expect(n.version).toMatch(/^\d+\.\d+/);
      expect(n.highlights.length).toBeGreaterThan(0);
    }
  });
});

describe('sanitizer + strip report', () => {
  it('strips class/iframe but keeps font/center/table', () => {
    const out = sanitizeNf('<div class="x"><font size="5">hi</font><center>c</center></div><iframe src="y"></iframe>');
    expect(out).toContain('<font size="5">hi</font>');
    expect(out).toContain('<center>c</center>');
    expect(out).not.toContain('class=');
    expect(out).not.toContain('iframe');
  });
  it('reports what would be stripped', () => {
    const r = buildSanitizeReport('<div class="x" onclick="z()"><iframe></iframe></div>');
    expect(r.clean).toBe(false);
    expect(r.strippedTags.map((t) => t.name)).toContain('iframe');
    expect(r.strippedAttrs.map((a) => a.name)).toEqual(expect.arrayContaining(['class', 'onclick']));
  });
});
