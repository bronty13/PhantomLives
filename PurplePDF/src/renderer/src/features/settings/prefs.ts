/**
 * @file prefs.ts — typed renderer client for the main-process
 * preferences store. Mirrors the schema declared in `src/main/prefs.ts`.
 */

export interface CustomTextStamp {
  id: string;
  kind: 'text';
  label: string;
  style: 'rect' | 'mark';
  color: string;
  width: number;
  height: number;
  subtitleMode: 'none' | 'date' | 'user' | 'both';
}

export interface CustomImageStamp {
  id: string;
  kind: 'image';
  label: string;
  imageBytesB64: string;
  mime: 'image/png' | 'image/jpeg';
  naturalWidth: number;
  naturalHeight: number;
  width: number;
  height: number;
  defaultIncludeSubtitle: boolean;
}

export type CustomStamp = CustomTextStamp | CustomImageStamp;

export interface Preferences {
  version: number;
  customStamps: CustomStamp[];
  hiddenBuiltinStampIds: string[];
}

interface PrefsBridge {
  prefsGet: () => Promise<Preferences>;
  prefsSet: (patch: Partial<Preferences>) => Promise<Preferences>;
  prefsReset: () => Promise<Preferences>;
}

function bridge(): PrefsBridge | null {
  const api = (window as unknown as { purplePDF?: PrefsBridge }).purplePDF;
  if (!api?.prefsGet || !api?.prefsSet || !api?.prefsReset) return null;
  return api;
}

export async function loadPrefs(): Promise<Preferences> {
  const b = bridge();
  if (!b) return { version: 1, customStamps: [], hiddenBuiltinStampIds: [] };
  return await b.prefsGet();
}

export async function savePrefs(patch: Partial<Preferences>): Promise<Preferences> {
  const b = bridge();
  if (!b) throw new Error('Preferences bridge unavailable');
  return await b.prefsSet(patch);
}

export async function resetPrefs(): Promise<Preferences> {
  const b = bridge();
  if (!b) throw new Error('Preferences bridge unavailable');
  return await b.prefsReset();
}

/** Base64 ⇄ bytes helpers for image-stamp payloads. */
export function bytesToBase64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

export function base64ToBytes(b64: string): Uint8Array {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}
