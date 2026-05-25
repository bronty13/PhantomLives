import { describe, expect, it } from 'vitest';
import {
  exportJson,
  exportZip,
  exportBundle,
  importBundle,
  mergeImported
} from '../../src/renderer/src/features/settings/stampIO';
import type { CustomStamp } from '../../src/renderer/src/features/settings/prefs';

const textStamp: CustomStamp = {
  id: 'txt-1',
  kind: 'text',
  label: 'CUSTOM',
  style: 'rect',
  color: '#7C3AED',
  width: 200,
  height: 60,
  subtitleMode: 'both'
};

// 1x1 PNG (transparent) base64.
const tinyPngB64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

const imageStamp: CustomStamp = {
  id: 'img-1',
  kind: 'image',
  label: 'Logo',
  imageBytesB64: tinyPngB64,
  mime: 'image/png',
  naturalWidth: 1,
  naturalHeight: 1,
  width: 100,
  height: 100,
  defaultIncludeSubtitle: false
};

describe('stamp import/export', () => {
  it('JSON round-trips text stamps losslessly', async () => {
    const bytes = exportJson([textStamp]);
    const back = await importBundle(bytes);
    expect(back).toEqual([textStamp]);
  });

  it('ZIP round-trips image stamps and reattaches image bytes', async () => {
    const bytes = await exportZip([imageStamp]);
    const back = await importBundle(bytes);
    expect(back).toHaveLength(1);
    const s = back[0];
    expect(s.kind).toBe('image');
    if (s.kind !== 'image') throw new Error('expected image');
    expect(s.id).toBe('img-1');
    expect(s.label).toBe('Logo');
    expect(s.mime).toBe('image/png');
    expect(s.imageBytesB64).toBe(tinyPngB64);
  });

  it('exportBundle picks ZIP iff any stamp has image bytes', async () => {
    const onlyText = await exportBundle([textStamp]);
    expect(onlyText.ext).toBe('purplestamps.json');
    const mixed = await exportBundle([textStamp, imageStamp]);
    expect(mixed.ext).toBe('purplestamps');
  });

  it('mergeImported "append" renames conflicting IDs', () => {
    const dup: CustomStamp = { ...textStamp, label: 'CUSTOM v2' };
    const merged = mergeImported([textStamp], [dup], 'append');
    expect(merged).toHaveLength(2);
    expect(merged[0].id).toBe('txt-1');
    expect(merged[1].id).toBe('txt-1-2');
    expect(merged[1].label).toContain('(2)');
  });

  it('mergeImported "replace-conflicts" overwrites in place', () => {
    const replacement: CustomStamp = { ...textStamp, label: 'REPLACED' };
    const merged = mergeImported([textStamp], [replacement], 'replace-conflicts');
    expect(merged).toHaveLength(1);
    expect(merged[0].label).toBe('REPLACED');
  });

  it('mergeImported "replace-all" discards existing customs', () => {
    const merged = mergeImported([textStamp, imageStamp], [textStamp], 'replace-all');
    expect(merged).toEqual([textStamp]);
  });

  it('importBundle rejects empty / invalid manifests', async () => {
    const invalid = new TextEncoder().encode(JSON.stringify({ version: 1, stamps: [] }));
    await expect(importBundle(invalid)).rejects.toThrow();
  });
});
