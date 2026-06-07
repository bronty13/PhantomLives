import { describe, it, expect } from 'vitest';
import { exportBundleJson, parseBundleFile } from '../src/storage/bundleIO';
import { SEED_THEMES } from '../src/model/seedThemes';
import { makeBundle, makeItem } from '../src/model/factory';
import { SCHEMA_VERSION } from '../src/model/types';

describe('bundle import/export', () => {
  const theme = SEED_THEMES[0];
  const bundle = makeBundle({ title: 'My Calendar', year: 2026, month: 7, themeId: theme.id, weekStartsOn: 0 });
  bundle.days['2026-07-04'] = { date: '2026-07-04', holidayIds: ['independence-day'], items: [makeItem('churchEvent', 0, 'Picnic')] };

  it('round-trips a bundle through JSON', () => {
    const json = exportBundleJson(bundle, theme);
    const parsed = parseBundleFile(json);
    expect(parsed.bundle.title).toBe('My Calendar');
    expect(parsed.bundle.days['2026-07-04'].items[0].text).toBe('Picnic');
    expect(parsed.theme.id).toBe(theme.id);
    expect(parsed.schemaVersion).toBe(SCHEMA_VERSION);
  });

  it('rejects non-JSON', () => {
    expect(() => parseBundleFile('not json')).toThrow();
  });

  it('rejects a file missing bundle/theme', () => {
    expect(() => parseBundleFile(JSON.stringify({ schemaVersion: 1 }))).toThrow();
  });

  it('rejects a newer schema version', () => {
    const json = JSON.stringify({ schemaVersion: SCHEMA_VERSION + 1, bundle: bundle, theme });
    expect(() => parseBundleFile(json)).toThrow(/newer version/);
  });
});
