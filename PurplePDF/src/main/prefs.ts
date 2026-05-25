/**
 * @file prefs.ts — per-install user preferences (Settings window state).
 *
 * Persists to `<userData>/purple-pdf-prefs.json` via `electron-store`.
 * The schema is versioned so we can run migrations across releases
 * without losing user customisations.
 */
import Store from 'electron-store';

/** Image-stamp bytes are base64-encoded so they survive JSON round-trips. */
export interface CustomTextStamp {
  id: string;
  kind: 'text';
  /** Big label, e.g. "URGENT". */
  label: string;
  /** "rect" = bordered box with label; "mark" = single glyph (✓ / ✗). */
  style: 'rect' | 'mark';
  /** CSS hex color used for border and text. */
  color: string;
  /** Default size (PDF points). */
  width: number;
  height: number;
  /** Default subtitle behavior when this stamp is armed. */
  subtitleMode: 'none' | 'date' | 'user' | 'both';
}

export interface CustomImageStamp {
  id: string;
  kind: 'image';
  /** Display name shown in the picker / Stamps tab list. */
  label: string;
  /** Base64-encoded image bytes (PNG or JPEG). */
  imageBytesB64: string;
  /** MIME of the bytes. */
  mime: 'image/png' | 'image/jpeg';
  /** Intrinsic pixel dimensions. */
  naturalWidth: number;
  naturalHeight: number;
  /** Default placement size (PDF points); aspect ratio preserved. */
  width: number;
  height: number;
  /** When true, overlay "By {user} at {date}" beneath the image stamp. */
  defaultIncludeSubtitle: boolean;
}

export type CustomStamp = CustomTextStamp | CustomImageStamp;

export interface Preferences {
  /** Bumped whenever the schema changes; migrations run on load. */
  version: number;
  /** User-defined stamps that appear alongside built-in presets. */
  customStamps: CustomStamp[];
  /** IDs of built-in presets the user has hidden from the picker. */
  hiddenBuiltinStampIds: string[];
}

const DEFAULTS: Preferences = {
  version: 1,
  customStamps: [],
  hiddenBuiltinStampIds: []
};

let store: Store<Preferences> | null = null;
function getStore(): Store<Preferences> {
  if (!store) {
    store = new Store<Preferences>({
      name: 'purple-pdf-prefs',
      defaults: DEFAULTS
    });
    migrate(store);
  }
  return store;
}

/** Run schema migrations in-place. New versions append cases here. */
function migrate(s: Store<Preferences>): void {
  const v = s.get('version', 0);
  if (v < 1) {
    // First-run / pre-1.1.0: ensure required keys exist.
    s.set('customStamps', s.get('customStamps', []) ?? []);
    s.set('hiddenBuiltinStampIds', s.get('hiddenBuiltinStampIds', []) ?? []);
    s.set('version', 1);
  }
  // Future: if (v < 2) { ... s.set('version', 2); }
}

export function getPreferences(): Preferences {
  const s = getStore();
  return {
    version: s.get('version', DEFAULTS.version),
    customStamps: s.get('customStamps', DEFAULTS.customStamps),
    hiddenBuiltinStampIds: s.get('hiddenBuiltinStampIds', DEFAULTS.hiddenBuiltinStampIds)
  };
}

/** Merge-set: only provided keys are overwritten. */
export function setPreferences(patch: Partial<Preferences>): Preferences {
  const s = getStore();
  for (const [k, v] of Object.entries(patch)) {
    if (k === 'version') continue; // version is managed by migrations
    s.set(k as keyof Preferences, v as never);
  }
  return getPreferences();
}

export function resetPreferences(): Preferences {
  const s = getStore();
  s.set('version', DEFAULTS.version);
  s.set('customStamps', DEFAULTS.customStamps);
  s.set('hiddenBuiltinStampIds', DEFAULTS.hiddenBuiltinStampIds);
  return getPreferences();
}
