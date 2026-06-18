import { describe, it, expect } from 'vitest';
import { classifyNfButton, isNiteFlirtUrl, isNiteFlirtFileManagerUrl } from '../src/shared/import/buttonPatterns';

describe('NiteFlirt URL classification (the link-vs-button gate)', () => {
  it('treats only niteflirt.com anchors as buttons', () => {
    expect(isNiteFlirtUrl('https://www.niteflirt.com/goodies/1')).toBe(true);
    expect(isNiteFlirtUrl('https://niteflirt.com/x')).toBe(true);
    expect(isNiteFlirtUrl('https://example.com/img')).toBe(false);
    expect(isNiteFlirtUrl('https://amazon.com/wishlist')).toBe(false);
  });

  it('declines (null) for non-NiteFlirt URLs so they fall through to link+image', () => {
    expect(classifyNfButton('https://example.com/buy')).toBeNull();
  });

  it('classifies tribute, flirt-call, and goody sub-types', () => {
    expect(classifyNfButton('https://www.niteflirt.com/tributes/pay')).toBe('tributeButton');
    expect(classifyNfButton('https://www.niteflirt.com/listings/show/123')).toBe('flirtButton');
    expect(classifyNfButton('https://www.niteflirt.com/goodies/123')).toBe('goodyButton');
  });

  it('defaults unknown NiteFlirt paths to goody', () => {
    expect(classifyNfButton('https://www.niteflirt.com/something/else')).toBe('goodyButton');
  });

  it('recognizes File Manager media URLs', () => {
    expect(isNiteFlirtFileManagerUrl('https://www.niteflirt.com/fm/f/abc/def')).toBe(true);
    expect(isNiteFlirtFileManagerUrl('https://example.com/fm/f/abc/def')).toBe(false);
  });
});
