// Deploy orchestration — turn a quiz + branding into a downloadable artifact.

import type { Branding, Quiz } from '../../shared/model';
import type { DeployFormat } from '../../shared/payload';
import { PLAYER_TEMPLATE } from '../generated/playerTemplate';
import { buildSingleFileHtml } from './injectPayload';
import { buildZipPlan, packZip } from './buildZip';
import { downloadBlob } from './download';

export async function deployQuiz(
  quiz: Quiz,
  branding: Branding,
  format: DeployFormat,
  generatedAt: string = new Date().toISOString(),
): Promise<{ filename: string; blob: Blob }> {
  if (format === 'single') {
    const { filename, html } = buildSingleFileHtml(PLAYER_TEMPLATE, quiz, branding, generatedAt);
    return { filename, blob: new Blob([html], { type: 'text/html' }) };
  }
  const plan = buildZipPlan(PLAYER_TEMPLATE, quiz, branding, generatedAt);
  return { filename: plan.filename, blob: await packZip(plan) };
}

export async function deployAndDownload(
  quiz: Quiz,
  branding: Branding,
  format: DeployFormat,
): Promise<string> {
  const { filename, blob } = await deployQuiz(quiz, branding, format);
  downloadBlob(filename, blob);
  return filename;
}
