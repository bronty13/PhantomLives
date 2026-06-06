// Inject a quiz payload into the embedded player template. Pure + testable.

import type { Branding, Quiz, Wheel } from '../../shared/model';
import { buildPayload } from '../../shared/payload';
import { buildWheelPayload } from '../../shared/wheelPayload';
import { jsonForScript } from '../../shared/dataurl';
import { slugify } from '../../shared/util';

export const PAYLOAD_MARKER = '<!--QUIZ_PAYLOAD-->';

/** Replace the payload marker once. A replacer fn avoids `$&`-style pattern bugs. */
export function injectScript(template: string, scriptHtml: string): string {
  if (!template.includes(PAYLOAD_MARKER)) {
    throw new Error('Player template is missing the <!--QUIZ_PAYLOAD--> marker.');
  }
  return template.replace(PAYLOAD_MARKER, () => scriptHtml);
}

/** Single-file deploy: inline <script> sets window.__QUIZ__ before the player boots. */
export function buildSingleFileHtml(
  template: string,
  quiz: Quiz,
  branding: Branding,
  generatedAt: string,
): { filename: string; html: string } {
  const payload = buildPayload(quiz, branding, 'single', generatedAt);
  const script = `<script>window.__QUIZ__=${jsonForScript(payload)}</script>`;
  return { filename: `${slugify(quiz.name)}.html`, html: injectScript(template, script) };
}

/** Single-file deploy for a wheel: inline <script> sets window.__QUIZ__ before boot. */
export function buildWheelSingleFileHtml(
  template: string,
  wheel: Wheel,
  branding: Branding,
  generatedAt: string,
): { filename: string; html: string } {
  const payload = buildWheelPayload(wheel, branding, 'single', generatedAt);
  const script = `<script>window.__QUIZ__=${jsonForScript(payload)}</script>`;
  return { filename: `${slugify(wheel.name)}.html`, html: injectScript(template, script) };
}
