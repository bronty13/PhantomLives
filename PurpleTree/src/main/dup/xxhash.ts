/**
 * @file xxhash.ts — pure-WASM xxhash wrapper for the duplicate finder.
 *
 * We deliberately use `xxhash-wasm` (the wasm is inlined as base64 in its JS,
 * so there is no separate `.wasm` file to unpack from the asar) instead of a
 * native node addon. A native addon would drag node-gyp/prebuild into the
 * build and fight electron-builder's universal-mac + win-x64 packaging; the
 * wasm module runs identically on every arch with zero rebuild.
 *
 * xxhash is non-cryptographic, which is fine: we only use it to *confirm*
 * byte-identical duplicates, and never delete without explicit user action.
 */
import { open } from 'node:fs/promises';
import xxhashInit from 'xxhash-wasm';

type Hasher = Awaited<ReturnType<typeof xxhashInit>>;
let hasherPromise: Promise<Hasher> | null = null;

async function getHasher(): Promise<Hasher> {
  if (!hasherPromise) hasherPromise = xxhashInit();
  return hasherPromise;
}

/** Hash an in-memory buffer (used for the first-N-KB partial pass). */
export async function hashBuffer(bytes: Uint8Array): Promise<string> {
  const h = await getHasher();
  const c = h.create64();
  c.update(bytes);
  return c.digest().toString(16);
}

/** Hash the first `maxBytes` of a file (partial pass). */
export async function hashFilePartial(path: string, maxBytes: number): Promise<string> {
  const fd = await open(path, 'r');
  try {
    const buf = Buffer.allocUnsafe(maxBytes);
    const { bytesRead } = await fd.read(buf, 0, maxBytes, 0);
    return hashBuffer(buf.subarray(0, bytesRead));
  } finally {
    await fd.close();
  }
}

/** Hash an entire file by streaming fixed-size chunks (never loads it whole). */
export async function hashFileFull(path: string, chunkSize = 1 << 20): Promise<string> {
  const h = await getHasher();
  const c = h.create64();
  const fd = await open(path, 'r');
  try {
    const buf = Buffer.allocUnsafe(chunkSize);
    for (;;) {
      const { bytesRead } = await fd.read(buf, 0, chunkSize, null);
      if (bytesRead <= 0) break;
      c.update(buf.subarray(0, bytesRead));
    }
    return c.digest().toString(16);
  } finally {
    await fd.close();
  }
}
