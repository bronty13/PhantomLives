import { describe, expect, it } from 'vitest';
import { sanitizeHtml } from '../src/shared/sanitize';

describe('sanitizeHtml', () => {
  it('keeps allowed formatting', () => {
    const out = sanitizeHtml('<p>Hello <strong>world</strong> and <em>more</em></p>');
    expect(out).toContain('<strong>world</strong>');
    expect(out).toContain('<em>more</em>');
  });
  it('strips scripts and event handlers', () => {
    const out = sanitizeHtml('<p onclick="evil()">x</p><script>steal()</script><img src=x onerror=hack>');
    expect(out).not.toContain('<script');
    expect(out).not.toContain('onerror');
    expect(out).not.toContain('onclick');
  });
});
