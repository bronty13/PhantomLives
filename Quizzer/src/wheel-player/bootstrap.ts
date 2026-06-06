// Reads the deployed wheel from window.__QUIZ__ (injected by the creator), or falls
// back to a demo wheel in dev mode. Never fetches — must work under file://.

import type { Branding, Wheel } from '../shared/model';
import type { WheelDeployPayload } from '../shared/wheelPayload';
import { buildWheelPayload } from '../shared/wheelPayload';
import { demoWheel } from '../shared/factory';

// Both players read window.__QUIZ__; each only ever receives its own payload shape.
// Read via a local cast so this bundle doesn't globally re-type a window property
// the quiz player declares with a different (quiz) payload type.
function injectedPayload(): WheelDeployPayload | undefined {
  return (window as unknown as { __QUIZ__?: WheelDeployPayload }).__QUIZ__;
}

export interface WheelData {
  wheel: Wheel;
  branding: Branding;
  format: WheelDeployPayload['format'];
}

function devFallbackPayload(): WheelDeployPayload {
  const { wheel, branding } = demoWheel();
  return buildWheelPayload(wheel, branding, 'single', new Date().toISOString());
}

export function loadWheelData(): WheelData {
  const payload = injectedPayload() ?? devFallbackPayload();
  return { wheel: payload.wheel, branding: payload.branding, format: payload.format };
}
