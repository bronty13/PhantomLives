import { describe, expect, it } from 'vitest';
import { buildWheelPayload } from '../src/shared/wheelPayload';
import { demoWheel } from '../src/shared/factory';
import { jsonForScript } from '../src/shared/dataurl';

describe('buildWheelPayload', () => {
  const { wheel, branding } = demoWheel();
  const payload = buildWheelPayload(wheel, branding, 'single', '2026-06-06T00:00:00Z');

  it('tags the payload as a wheel with the right format and metadata', () => {
    expect(payload.kind).toBe('wheel');
    expect(payload.format).toBe('single');
    expect(payload.generatedAt).toBe('2026-06-06T00:00:00Z');
    expect(payload.schemaVersion).toBeGreaterThanOrEqual(1);
  });

  it('ships the wheel verbatim — choices are public plaintext (no hiding)', () => {
    expect(payload.wheel).toEqual(wheel);
    const encoded = jsonForScript(payload);
    expect(encoded).toContain('Free Coffee');
    expect(encoded).toContain('"weight":1');
  });

  it('carries the branding through unchanged', () => {
    expect(payload.branding).toEqual(branding);
  });
});
