// data: URI <-> bytes, and a JSON-in-HTML safe encoder.

export interface DecodedDataUri {
  mime: string;
  bytes: Uint8Array;
}

export function dataUriToBytes(dataUri: string): DecodedDataUri {
  const m = /^data:([^;,]*)(;base64)?,(.*)$/s.exec(dataUri);
  if (!m) throw new Error('Not a data URI');
  const mime = m[1] || 'application/octet-stream';
  const isBase64 = !!m[2];
  const data = m[3];
  if (isBase64) {
    const binary = atob(data);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return { mime, bytes };
  }
  return { mime, bytes: new TextEncoder().encode(decodeURIComponent(data)) };
}

export function bytesToDataUri(mime: string, bytes: Uint8Array): string {
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return `data:${mime};base64,${btoa(binary)}`;
}

/** A reasonable file extension for a mime type. */
export function extForMime(mime: string): string {
  const map: Record<string, string> = {
    'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif',
    'image/webp': 'webp', 'image/svg+xml': 'svg',
    'video/mp4': 'mp4', 'video/webm': 'webm', 'video/quicktime': 'mov',
    'font/ttf': 'ttf', 'font/otf': 'otf', 'application/font-sfnt': 'ttf',
    'font/woff': 'woff', 'font/woff2': 'woff2',
  };
  return map[mime] ?? 'bin';
}

/**
 * JSON encoded to embed safely inside an inline <script>. Escapes `<` (kills
 * </script> / <!-- breakouts) and the U+2028/U+2029 line separators that break
 * some script parsers.
 */
export function jsonForScript(value: unknown): string {
  const LS = String.fromCharCode(0x2028);
  const PS = String.fromCharCode(0x2029);
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .split(LS).join('\\u2028')
    .split(PS).join('\\u2029');
}
