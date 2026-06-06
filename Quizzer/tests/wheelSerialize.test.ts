import { describe, expect, it } from 'vitest';
import { exportWheelBundleJson, parseWheelBundle } from '../src/creator/storage/wheelBundle';
import { demoWheel } from '../src/shared/factory';

describe('wheel bundle round-trip', () => {
  it('exports and re-parses an identical bundle', () => {
    const { wheel, branding } = demoWheel();
    const json = exportWheelBundleJson(wheel, branding);
    const back = parseWheelBundle(json);
    expect(back.wheel).toEqual(wheel);
    expect(back.branding).toEqual(branding);
  });

  it('rejects non-JSON', () => {
    expect(() => parseWheelBundle('not json {')).toThrow(/JSON/);
  });

  it('rejects a non-wheel bundle', () => {
    expect(() => parseWheelBundle(JSON.stringify({ schemaVersion: 1 }))).toThrow(/wheel/);
  });

  it('rejects a wheel with no choices array', () => {
    const bad = JSON.stringify({ schemaVersion: 1, wheel: { name: 'x' }, branding: {} });
    expect(() => parseWheelBundle(bad)).toThrow(/choices/);
  });

  it('rejects a bundle from a newer schema', () => {
    const { wheel, branding } = demoWheel();
    const bad = JSON.stringify({ schemaVersion: 999, wheel, branding });
    expect(() => parseWheelBundle(bad)).toThrow(/newer/);
  });
});
