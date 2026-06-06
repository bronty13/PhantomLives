// Answer-key obfuscation.
//
// IMPORTANT: this is DETERRENCE, NOT SECURITY. Client-side grading means the
// correct answers must exist in the deployed file, so a determined respondent can
// always recover them. This XOR+base64 scramble only stops casual View-Source
// ("the answers are right there"). Do not rely on it for anything that matters.

const KEY = 'quizzer-v1-obfuscation-key';

function xorBytes(bytes: Uint8Array): Uint8Array {
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ KEY.charCodeAt(i % KEY.length);
  }
  return out;
}

/** base64 of arbitrary bytes, chunked to avoid call-stack overflow on large keys. */
function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function obfuscate(value: unknown): string {
  const json = JSON.stringify(value);
  const bytes = new TextEncoder().encode(json);
  return bytesToBase64(xorBytes(bytes));
}

export function deobfuscate<T>(blob: string): T {
  const bytes = base64ToBytes(blob);
  const json = new TextDecoder().decode(xorBytes(bytes));
  return JSON.parse(json) as T;
}
