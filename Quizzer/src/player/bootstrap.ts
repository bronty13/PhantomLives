// Reads the deployed quiz from window.__QUIZ__ (injected by the creator), or falls
// back to a demo bundle in dev mode. Never fetches — must work under file://.

import type { Branding, Question, Quiz } from '../shared/model';
import type { DeployPayload } from '../shared/payload';
import { buildPayload, resolveQuestions } from '../shared/payload';
import { demoBundle } from '../shared/factory';

declare global {
  interface Window {
    __QUIZ__?: DeployPayload;
  }
}

export interface PlayerData {
  quiz: Quiz;
  branding: Branding;
  questions: Question[]; // full questions, answers merged in
  format: DeployPayload['format'];
}

function devFallbackPayload(): DeployPayload {
  const { quiz, branding } = demoBundle();
  return buildPayload(quiz, branding, 'single', new Date().toISOString());
}

export function loadPlayerData(): PlayerData {
  const payload = window.__QUIZ__ ?? devFallbackPayload();
  return {
    quiz: payload.quiz,
    branding: payload.branding,
    questions: resolveQuestions(payload),
    format: payload.format,
  };
}
