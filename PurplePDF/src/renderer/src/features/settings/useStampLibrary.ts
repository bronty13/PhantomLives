/**
 * @file useStampLibrary.ts — React hook that loads custom stamps from
 * the main-process preferences store, merges them with the built-in
 * presets, and exposes mutation helpers backed by `prefs:set`.
 *
 * Single source of truth for the EditPalette stamp picker AND the
 * Settings → Stamps tab.
 */

import { useCallback, useEffect, useState } from 'react';
import { STAMP_PRESETS, type StampPreset } from '../annotate/stamps';
import { loadPrefs, savePrefs, type CustomStamp, type Preferences } from './prefs';

export interface MergedStampEntry {
  kind: 'builtin' | 'custom-text' | 'custom-image';
  id: string;
  label: string;
  /** Underlying preset (built-ins) — used by EditPalette to arm. */
  preset?: StampPreset;
  custom?: CustomStamp;
  hidden?: boolean;
}

interface UseStampLibrary {
  prefs: Preferences | null;
  loading: boolean;
  /** Built-ins (after hide filter) followed by customs, in display order. */
  merged: MergedStampEntry[];
  /** All built-ins including hidden ones (for the manage tab). */
  allBuiltins: StampPreset[];
  reload: () => Promise<void>;
  saveCustoms: (next: CustomStamp[]) => Promise<void>;
  saveHiddenBuiltins: (ids: string[]) => Promise<void>;
}

export function useStampLibrary(): UseStampLibrary {
  const [prefs, setPrefs] = useState<Preferences | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const p = await loadPrefs();
      setPrefs(p);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const saveCustoms = useCallback(async (next: CustomStamp[]) => {
    const updated = await savePrefs({ customStamps: next });
    setPrefs(updated);
  }, []);

  const saveHiddenBuiltins = useCallback(async (ids: string[]) => {
    const updated = await savePrefs({ hiddenBuiltinStampIds: ids });
    setPrefs(updated);
  }, []);

  const hiddenSet = new Set(prefs?.hiddenBuiltinStampIds ?? []);
  const merged: MergedStampEntry[] = [
    ...STAMP_PRESETS.filter((p) => !hiddenSet.has(p.id)).map<MergedStampEntry>((p) => ({
      kind: 'builtin',
      id: p.id,
      label: p.label,
      preset: p
    })),
    ...(prefs?.customStamps ?? []).map<MergedStampEntry>((c) => ({
      kind: c.kind === 'image' ? 'custom-image' : 'custom-text',
      id: c.id,
      label: c.label,
      custom: c
    }))
  ];

  return {
    prefs,
    loading,
    merged,
    allBuiltins: STAMP_PRESETS,
    reload,
    saveCustoms,
    saveHiddenBuiltins
  };
}
