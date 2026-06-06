// The window.__QUIZ__ contract for the Spin-the-Wheel player. Unlike the quiz
// payload, a wheel has no secret — its choices are printed on the wheel face — so
// there is NO obfuscation and NO strip/restore. The wheel ships verbatim.

import type { Branding, Wheel } from './model';
import { SCHEMA_VERSION } from './model';
import type { DeployFormat } from './payload';

export interface WheelDeployPayload {
  schemaVersion: number;
  kind: 'wheel'; // discriminant vs the quiz payload (each player reads its own)
  format: DeployFormat;
  generatedAt: string;
  wheel: Wheel;
  branding: Branding;
}

/** Build the deploy payload for a wheel + branding (nothing hidden). */
export function buildWheelPayload(
  wheel: Wheel,
  branding: Branding,
  format: DeployFormat,
  generatedAt: string,
): WheelDeployPayload {
  return {
    schemaVersion: SCHEMA_VERSION,
    kind: 'wheel',
    format,
    generatedAt,
    wheel,
    branding,
  };
}
