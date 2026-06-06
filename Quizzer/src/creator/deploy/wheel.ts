// Deploy orchestration for the Spin-the-Wheel activity — turn a wheel + branding
// into a downloadable, self-contained artifact. Mirrors deploy/index.ts but uses
// the wheel player template and the (no-secret) wheel payload.

import type { Branding, Wheel } from '../../shared/model';
import type { DeployFormat } from '../../shared/payload';
import { WHEEL_TEMPLATE } from '../generated/wheelTemplate';
import { buildWheelSingleFileHtml } from './injectPayload';
import { buildWheelZipPlan, packZip } from './buildZip';
import { downloadBlob } from './download';

export async function deployWheel(
  wheel: Wheel,
  branding: Branding,
  format: DeployFormat,
  generatedAt: string = new Date().toISOString(),
): Promise<{ filename: string; blob: Blob }> {
  if (format === 'single') {
    const { filename, html } = buildWheelSingleFileHtml(WHEEL_TEMPLATE, wheel, branding, generatedAt);
    return { filename, blob: new Blob([html], { type: 'text/html' }) };
  }
  const plan = buildWheelZipPlan(WHEEL_TEMPLATE, wheel, branding, generatedAt);
  return { filename: plan.filename, blob: await packZip(plan) };
}

export async function deployWheelAndDownload(
  wheel: Wheel,
  branding: Branding,
  format: DeployFormat,
): Promise<string> {
  const { filename, blob } = await deployWheel(wheel, branding, format);
  downloadBlob(filename, blob);
  return filename;
}
