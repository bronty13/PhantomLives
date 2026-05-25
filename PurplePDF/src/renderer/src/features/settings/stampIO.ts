/**
 * @file stampIO.ts — import / export helpers for the custom stamp
 * library. Supports two on-disk formats:
 *
 *   - `.purplestamps.json` — a plain JSON file describing one or more
 *     stamps. Used when no stamp uses image bytes (lossless, easy to
 *     hand-edit / version-control).
 *   - `.purplestamps`      — a JSZip archive (`manifest.json` + image
 *     blobs in `images/<id>.<ext>`). Used whenever any stamp in the
 *     collection has image bytes. Lossless.
 *
 * Import auto-detects the file type from the bytes (zip magic
 * `PK\x03\x04`) so either extension is acceptable on disk.
 */

import JSZip from 'jszip';
import {
  type CustomStamp,
  type CustomImageStamp,
  bytesToBase64,
  base64ToBytes
} from './prefs';

export const STAMP_BUNDLE_VERSION = 1;

interface BundleManifest {
  version: number;
  exportedAt: string;
  /** Stamps with image bytes have `imageBytesB64` cleared; bytes live in
   *  `images/<id>.<ext>` inside the ZIP. JSON bundles inline base64. */
  stamps: CustomStamp[];
}

function newBundleManifest(stamps: CustomStamp[]): BundleManifest {
  return {
    version: STAMP_BUNDLE_VERSION,
    exportedAt: new Date().toISOString(),
    stamps
  };
}

function hasImageStamps(stamps: CustomStamp[]): boolean {
  return stamps.some((s) => s.kind === 'image');
}

function extFor(mime: 'image/png' | 'image/jpeg'): 'png' | 'jpg' {
  return mime === 'image/jpeg' ? 'jpg' : 'png';
}

/** Build a JSON-encoded bundle (image stamps inlined as base64). */
export function exportJson(stamps: CustomStamp[]): Uint8Array {
  const manifest = newBundleManifest(stamps);
  const json = JSON.stringify(manifest, null, 2);
  return new TextEncoder().encode(json);
}

/** Build a ZIP-encoded bundle with image bytes split out into `images/`. */
export async function exportZip(stamps: CustomStamp[]): Promise<Uint8Array> {
  const zip = new JSZip();
  const stampsForManifest: CustomStamp[] = stamps.map((s) => {
    if (s.kind !== 'image') return s;
    const ext = extFor(s.mime);
    const bytes = base64ToBytes(s.imageBytesB64);
    zip.file(`images/${s.id}.${ext}`, bytes);
    // Strip base64 from the manifest copy; on import we re-read it.
    return { ...s, imageBytesB64: '' };
  });
  zip.file('manifest.json', JSON.stringify(newBundleManifest(stampsForManifest), null, 2));
  return await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
}

/** Choose the right format based on payload, returning bytes + suggested ext. */
export async function exportBundle(
  stamps: CustomStamp[]
): Promise<{ bytes: Uint8Array; ext: 'purplestamps.json' | 'purplestamps' }> {
  if (hasImageStamps(stamps)) {
    return { bytes: await exportZip(stamps), ext: 'purplestamps' };
  }
  return { bytes: exportJson(stamps), ext: 'purplestamps.json' };
}

function looksLikeZip(bytes: Uint8Array): boolean {
  return bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04;
}

/** Parse either format and return validated stamps. */
export async function importBundle(bytes: Uint8Array): Promise<CustomStamp[]> {
  if (looksLikeZip(bytes)) {
    const zip = await JSZip.loadAsync(bytes);
    const manifestFile = zip.file('manifest.json');
    if (!manifestFile) throw new Error('Bundle is missing manifest.json');
    const manifest = JSON.parse(await manifestFile.async('string')) as BundleManifest;
    const stamps = validateStamps(manifest.stamps);
    // Reattach image bytes from the images/ directory.
    for (const s of stamps) {
      if (s.kind !== 'image' || s.imageBytesB64) continue;
      const ext = extFor(s.mime);
      const file = zip.file(`images/${s.id}.${ext}`) ?? zip.file(`images/${s.id}.png`) ?? zip.file(`images/${s.id}.jpg`);
      if (!file) throw new Error(`Bundle is missing image bytes for stamp "${s.label}" (${s.id})`);
      const data = await file.async('uint8array');
      (s as CustomImageStamp).imageBytesB64 = bytesToBase64(data);
    }
    return stamps;
  }
  const text = new TextDecoder().decode(bytes);
  const manifest = JSON.parse(text) as BundleManifest;
  return validateStamps(manifest.stamps);
}

function validateStamps(raw: unknown): CustomStamp[] {
  if (!Array.isArray(raw)) throw new Error('Bundle has no stamps array');
  const out: CustomStamp[] = [];
  for (const s of raw as Partial<CustomStamp>[]) {
    if (!s || typeof s !== 'object') continue;
    if (s.kind === 'text') {
      if (!s.id || !s.label) continue;
      out.push(s as CustomStamp);
    } else if (s.kind === 'image') {
      if (!s.id || !s.label || !s.mime) continue;
      out.push(s as CustomStamp);
    }
  }
  if (out.length === 0) throw new Error('Bundle contains no valid stamps');
  return out;
}

export type ConflictResolution = 'replace-all' | 'append' | 'replace-conflicts';

/** Merge an imported collection into the current customs per the user's resolution choice. */
export function mergeImported(
  current: CustomStamp[],
  imported: CustomStamp[],
  resolution: ConflictResolution
): CustomStamp[] {
  if (resolution === 'replace-all') return [...imported];
  const byId = new Map(current.map((s) => [s.id, s]));
  if (resolution === 'replace-conflicts') {
    for (const s of imported) byId.set(s.id, s);
    return Array.from(byId.values());
  }
  // append (rename conflicts)
  const out = [...current];
  const existingIds = new Set(out.map((s) => s.id));
  for (const s of imported) {
    if (!existingIds.has(s.id)) {
      out.push(s);
      existingIds.add(s.id);
      continue;
    }
    let suffix = 2;
    let candidate = `${s.id}-${suffix}`;
    while (existingIds.has(candidate)) {
      suffix += 1;
      candidate = `${s.id}-${suffix}`;
    }
    out.push({ ...s, id: candidate, label: `${s.label} (${suffix})` } as CustomStamp);
    existingIds.add(candidate);
  }
  return out;
}
