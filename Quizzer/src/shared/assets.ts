// Resolve an AssetRef to a usable element `src`. Both deploy formats funnel
// through here so the player stays format-agnostic — inline data-URI or relative
// file path, never a fetch().

import type { AssetRef } from './model';

export function resolveAsset(ref: AssetRef | undefined): string | undefined {
  if (!ref) return undefined;
  return ref.kind === 'inline' ? ref.dataUri : ref.path;
}

/** Rough byte size of an asset (decoded) — drives the inline-vs-externalize choice. */
export function assetByteSize(ref: AssetRef): number {
  if (ref.kind === 'file') return 0;
  const comma = ref.dataUri.indexOf(',');
  const b64 = comma >= 0 ? ref.dataUri.slice(comma + 1) : ref.dataUri;
  // base64 expands ~4/3; strip padding for a closer estimate.
  const padding = b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0;
  return Math.floor((b64.length * 3) / 4) - padding;
}

/** Assets at or below this size always inline; larger ones may externalize to a zip. */
export const INLINE_LIMIT_BYTES = 256 * 1024;
