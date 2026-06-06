// Wheel bundle import/export — a portable JSON file (wheel + its branding) used by
// the Export and Import actions on the Wheels screen. Uses a distinct
// `.wheelzer.json` extension so the importer can tell wheels from quizzes.

import type { Branding, Wheel, WheelBundle } from '../../shared/model';
import { SCHEMA_VERSION } from '../../shared/model';

export function exportWheelBundleJson(wheel: Wheel, branding: Branding): string {
  const bundle: WheelBundle = { schemaVersion: SCHEMA_VERSION, wheel, branding };
  return JSON.stringify(bundle, null, 2);
}

export function parseWheelBundle(json: string): WheelBundle {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    throw new Error('Not valid JSON.');
  }
  const b = data as Partial<WheelBundle>;
  if (!b || typeof b !== 'object' || !b.wheel || !b.branding) {
    throw new Error('File is not a Quizzer wheel bundle (missing wheel or branding).');
  }
  if (!Array.isArray(b.wheel.choices)) {
    throw new Error('Bundle wheel has no choices array.');
  }
  if ((b.schemaVersion ?? 1) > SCHEMA_VERSION) {
    throw new Error('Bundle was made with a newer version of Quizzer.');
  }
  return { schemaVersion: b.schemaVersion ?? SCHEMA_VERSION, wheel: b.wheel, branding: b.branding };
}
