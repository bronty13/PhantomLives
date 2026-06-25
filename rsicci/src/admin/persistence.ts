// Pause/resume persistence + session metadata for the administration copy.
//
// The whole survey state (answers, study id, method condition, timing) is saved
// to localStorage after every change so a participant can close and reopen the
// page without losing progress. Nothing leaves the device until they export.

import { INSTRUMENT_VERSION } from '../instrument/instrument'
import { PlainPayload, StoredAnswer } from '../datafile/datafile'
import { AnswerMap } from './skiplogic'

const STORAGE_KEY = 'rsicci.session.v1'

export interface Session {
  studyId: string
  methodCondition: string
  startedAt: number
  answers: AnswerMap
  moduleJOptIn: boolean
  moduleMs: Record<string, number>
}

function randomId(): string {
  const bytes = new Uint8Array(8)
  ;(globalThis as { crypto: Crypto }).crypto.getRandomValues(bytes)
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('').toUpperCase()
}

// Method condition randomizes only wording format (not semantic content). Only
// one wording set is authored in v0.1, so this is recorded for analysis, not yet
// varied in the displayed prompts.
function pickMethodCondition(): string {
  const r = new Uint32Array(1)
  ;(globalThis as { crypto: Crypto }).crypto.getRandomValues(r)
  return r[0] % 2 === 0 ? 'wording-A' : 'wording-B'
}

export function newSession(): Session {
  return {
    studyId: randomId(),
    methodCondition: pickMethodCondition(),
    startedAt: Date.now(),
    answers: {},
    moduleJOptIn: false,
    moduleMs: {},
  }
}

export function loadSession(): Session | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as Session) : null
  } catch {
    return null
  }
}

export function saveSession(s: Session): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(s))
  } catch {
    /* storage may be full or disabled; survey still works in-memory */
  }
}

export function clearSession(): void {
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    /* ignore */
  }
}

/** Record an answer with display-state and timestamps. */
export function setAnswer(answers: AnswerMap, variable: string, value: StoredAnswer['value']): AnswerMap {
  const prev = answers[variable]
  return {
    ...answers,
    [variable]: {
      value,
      displayed: true,
      shownAt: prev?.shownAt ?? Date.now(),
      answeredAt: Date.now(),
    },
  }
}

/** Mark an item displayed even if unanswered (so eligibility denominators are right). */
export function markDisplayed(answers: AnswerMap, variable: string): AnswerMap {
  if (answers[variable]?.displayed) return answers
  return { ...answers, [variable]: { value: answers[variable]?.value ?? null, displayed: true, shownAt: Date.now() } }
}

export function toPayload(s: Session, completed: boolean): PlainPayload {
  return {
    format: 'rsicci-plain-1',
    instrumentVersion: INSTRUMENT_VERSION,
    studyId: s.studyId,
    methodCondition: s.methodCondition,
    startedAt: s.startedAt,
    completedAt: completed ? Date.now() : null,
    moduleJOptIn: s.moduleJOptIn,
    answers: s.answers,
    qa: {
      attention: s.answers['QA_ATTENTION']?.value ?? undefined,
      totalMs: completed ? Date.now() - s.startedAt : undefined,
      moduleMs: s.moduleMs,
    },
  }
}
