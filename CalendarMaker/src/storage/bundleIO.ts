// Portable bundle import/export — a .cmcal.json file carrying the calendar plus
// the theme it uses, so it opens identically on another machine.

import type { BundleFile, CalendarBundle, Theme } from '../model/types';
import { APP_NAME, SCHEMA_VERSION } from '../model/types';

export function exportBundleJson(bundle: CalendarBundle, theme: Theme): string {
  const file: BundleFile = { schemaVersion: SCHEMA_VERSION, app: APP_NAME, bundle, theme };
  return JSON.stringify(file, null, 2);
}

export function parseBundleFile(json: string): BundleFile {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    throw new Error('Not valid JSON.');
  }
  const f = data as Partial<BundleFile>;
  if (!f || typeof f !== 'object' || !f.bundle || !f.theme) {
    throw new Error('File is not a CalendarMaker bundle (missing bundle or theme).');
  }
  if (typeof f.bundle.year !== 'number' || typeof f.bundle.month !== 'number' || !f.bundle.days) {
    throw new Error('Bundle is missing required calendar fields.');
  }
  if ((f.schemaVersion ?? 1) > SCHEMA_VERSION) {
    throw new Error('Bundle was made with a newer version of CalendarMaker.');
  }
  return { schemaVersion: f.schemaVersion ?? SCHEMA_VERSION, app: f.app ?? APP_NAME, bundle: f.bundle, theme: f.theme };
}
