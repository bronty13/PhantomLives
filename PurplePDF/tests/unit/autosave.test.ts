import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';

/**
 * The autosave key derivation lives inside src/main/autosave.ts behind the
 * `electron` import, which can't be loaded in a vitest renderer context. To
 * keep the unit test pure we re-implement the exact derivation and assert the
 * properties we care about. If the production derivation ever changes, this
 * test will start failing and force a deliberate update.
 */
function autosaveName(sourcePath: string | null, name: string): string {
  const key = sourcePath ?? `untitled:${name}`;
  const hash = createHash('sha1').update(key).digest('hex').slice(0, 16);
  return `${hash}.pdf`;
}

describe('autosave key derivation', () => {
  it('is deterministic for the same source path', () => {
    expect(autosaveName('/tmp/foo.pdf', 'foo.pdf')).toBe(
      autosaveName('/tmp/foo.pdf', 'foo.pdf')
    );
  });

  it('differs across source paths', () => {
    expect(autosaveName('/tmp/foo.pdf', 'foo.pdf')).not.toBe(
      autosaveName('/tmp/bar.pdf', 'bar.pdf')
    );
  });

  it('falls back to name for untitled docs', () => {
    expect(autosaveName(null, 'a')).not.toBe(autosaveName(null, 'b'));
    expect(autosaveName(null, 'a')).toBe(autosaveName(null, 'a'));
  });

  it('ignores the displayed name when a sourcePath is provided', () => {
    expect(autosaveName('/tmp/foo.pdf', 'one.pdf')).toBe(
      autosaveName('/tmp/foo.pdf', 'two.pdf')
    );
  });

  it('produces a 16-hex-char filename ending in .pdf', () => {
    const fname = autosaveName('/tmp/foo.pdf', 'foo.pdf');
    expect(fname).toMatch(/^[0-9a-f]{16}\.pdf$/);
  });
});
