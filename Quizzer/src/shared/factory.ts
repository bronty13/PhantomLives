// Factories for new entities + a demo bundle (used by the creator "new" actions and
// the player's dev-mode fallback).

import { nanoid } from 'nanoid';
import type {
  Branding,
  GlobalSettings,
  Question,
  QuestionType,
  Quiz,
  QuizBundle,
  Wheel,
  WheelBundle,
} from './model';
import {
  DEFAULT_GLOBAL_SETTINGS,
  SCHEMA_VERSION,
} from './model';

export const newId = (): string => nanoid(10);

export function makeBranding(name = 'Default Brand'): Branding {
  return {
    id: newId(),
    name,
    colors: {
      primary: '#5b2a86',
      secondary: '#8a4fbe',
      accent: '#d98324',
      bg: '#ffffff',
      text: '#1a1a1a',
    },
    font: { kind: 'builtin', family: 'Inter' },
    updatedAt: 0,
  };
}

export function makeQuestion(type: QuestionType, settings: GlobalSettings): Question {
  const base = {
    id: newId(),
    promptHtml: '<p></p>',
    weight: 1,
    correctText: settings.defaultCorrectText,
    incorrectText: settings.defaultIncorrectText,
    showCorrectAnswer: true,
  };
  switch (type) {
    case 'truefalse':
      return { ...base, type, correct: true };
    case 'mc':
      return {
        ...base, type, randomizeChoices: false,
        choices: [
          { id: newId(), text: '' },
          { id: newId(), text: '' },
        ],
        correctChoiceId: '',
      };
    case 'multi':
      return {
        ...base, type, randomizeChoices: false,
        choices: [
          { id: newId(), text: '' },
          { id: newId(), text: '' },
        ],
        correctChoiceIds: [],
      };
    case 'fill':
      return { ...base, type, caseSensitive: false, blanks: [{ id: newId(), accepted: [''] }] };
    case 'short':
      return { ...base, type, mode: 'paragraph', grading: { kind: 'manual' } };
  }
}

export function makeQuiz(brandingId: string, settings: GlobalSettings): Quiz {
  return {
    id: newId(),
    name: 'Untitled Quiz',
    introHtml: '<p>Welcome to the quiz.</p>',
    instructionsHtml: '',
    timeLimitSec: settings.defaultTimeLimitSec,
    attempts: settings.defaultAttempts,
    randomizeQuestions: settings.defaultRandomizeQuestions,
    passingPct: settings.defaultPassingPct,
    certificateEnabled: true,
    brandingId,
    questions: [],
    createdAt: 0,
    updatedAt: 0,
  };
}

export function makeWheel(brandingId: string, settings: GlobalSettings): Wheel {
  return {
    id: newId(),
    name: 'Untitled Wheel',
    descriptionHtml: `<p>${settings.defaultWheelDescription}</p>`,
    choices: [
      { id: newId(), text: '', weight: 1 },
      { id: newId(), text: '', weight: 1 },
    ],
    spinsPermitted: settings.defaultSpinsPermitted,
    soundDefaultOn: settings.defaultWheelSoundOn,
    pdfResultCount: settings.defaultPdfResultCount,
    resultLabel: settings.defaultResultLabel,
    spinSeconds: settings.defaultSpinSeconds,
    brandingId,
    createdAt: 0,
    updatedAt: 0,
  };
}

/** A fully-populated wheel bundle for previews and the wheel-player dev fallback. */
export function demoWheel(): WheelBundle {
  const branding = makeBranding('Acme Prizes');
  const s = DEFAULT_GLOBAL_SETTINGS;
  const labels = [
    'Free Coffee', 'Try Again', '10% Off', 'Gift Card',
    'Sticker Pack', 'Movie Ticket', 'Mystery Box', 'Bonus Spin',
  ];
  const wheel: Wheel = {
    ...makeWheel(branding.id, s),
    name: 'Prize Wheel',
    descriptionHtml: '<p>Spin the Wheel for a Prize.</p>',
    choices: labels.map((text) => ({ id: newId(), text, weight: 1 })),
  };
  return { schemaVersion: SCHEMA_VERSION, wheel, branding };
}

/** A small, fully-populated bundle for previews and dev mode. */
export function demoBundle(): QuizBundle {
  const branding = makeBranding('Acme Training');
  const s = DEFAULT_GLOBAL_SETTINGS;
  const c1 = newId();
  const c2 = newId();
  const c3 = newId();
  const m1 = newId();
  const m2 = newId();
  const m3 = newId();
  const quiz: Quiz = {
    ...makeQuiz(branding.id, s),
    name: 'Sample Knowledge Check',
    introHtml: '<p>This short demo quiz shows every question type. Good luck!</p>',
    instructionsHtml: '<p>Answer each question, then review your feedback.</p>',
    timeLimitSec: 600,
    questions: [
      { id: newId(), type: 'truefalse', promptHtml: '<p>The Earth orbits the Sun.</p>', weight: 1, correctText: s.defaultCorrectText, incorrectText: s.defaultIncorrectText, showCorrectAnswer: true, correct: true },
      { id: newId(), type: 'mc', promptHtml: '<p>What is the capital of France?</p>', weight: 1, correctText: s.defaultCorrectText, incorrectText: s.defaultIncorrectText, showCorrectAnswer: true, randomizeChoices: true, choices: [{ id: c1, text: 'London' }, { id: c2, text: 'Paris' }, { id: c3, text: 'Berlin' }], correctChoiceId: c2 },
      { id: newId(), type: 'multi', promptHtml: '<p>Which of these are prime numbers?</p>', weight: 2, correctText: s.defaultCorrectText, incorrectText: s.defaultIncorrectText, showCorrectAnswer: true, randomizeChoices: false, choices: [{ id: m1, text: '2' }, { id: m2, text: '4' }, { id: m3, text: '7' }], correctChoiceIds: [m1, m3] },
      { id: newId(), type: 'fill', promptHtml: '<p>Water is made of hydrogen and ______.</p>', weight: 1, correctText: s.defaultCorrectText, incorrectText: s.defaultIncorrectText, showCorrectAnswer: true, caseSensitive: false, blanks: [{ id: newId(), accepted: ['oxygen'] }] },
      { id: newId(), type: 'short', promptHtml: '<p>In one sentence, describe why the sky is blue.</p>', weight: 1, correctText: s.defaultCorrectText, incorrectText: s.defaultIncorrectText, showCorrectAnswer: false, mode: 'paragraph', grading: { kind: 'keyword', keywords: ['scatter', 'light'], minMatches: 1 } },
    ],
  };
  return { schemaVersion: SCHEMA_VERSION, quiz, branding };
}
