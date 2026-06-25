// Display gating for the survey runner.
//
// The item bank's `skip_logic` is free text. We implement the *structural* rules
// that change which items a participant sees — eligibility termination, the
// Module-E selected-theme indirection, and the Module-J opt-in — and otherwise
// default to "show the item" (the participant may skip or prefer-not-to-answer
// any sensitive item, so over-showing is safe and never forces a response).

import { Item, itemsByVar, themeByStem } from '../instrument/instrument'
import { StoredAnswer } from '../datafile/datafile'

export type AnswerMap = Record<string, StoredAnswer>

/** A theme is "endorsed" if its Appeal, Desire, or Practice is ≥ 1 (per routing). */
export function endorsedThemeStems(answers: AnswerMap): string[] {
  const out: string[] = []
  for (const [stem, theme] of themeByStem) {
    const vals = [theme.appeal, theme.desire, theme.practice]
      .map((v) => answers[v]?.value)
      .filter((v): v is number => typeof v === 'number' && v >= 1 && v <= 4)
    if (vals.length > 0) out.push(stem)
  }
  return out
}

/** Did the participant fail eligibility (ADM_AGE18 = No or Prefer-not)? */
export function isIneligible(answers: AnswerMap): boolean {
  const v = answers['ADM_AGE18']?.value
  return v === 0 || v === 99
}

/** Which Module-E slot does a TOP##_* follow-up belong to, and is it filled? */
function topSlotFilled(variable: string, answers: AnswerMap): boolean {
  const m = variable.match(/^TOP(\d{2})_/)
  if (!m) return false
  const slot = `TOP_THEME_${m[1]}`
  const chosen = answers[slot]?.value
  return typeof chosen === 'string' && chosen !== '' && chosen !== 'No additional theme' && chosen !== 'prefer not to answer'
}

/**
 * Should an item be displayed given the answers so far?
 * Returns false only for the structural gates we model.
 */
export function shouldDisplay(item: Item, answers: AnswerMap): boolean {
  // Module J body items (everything except the opt-in) require the opt-in = Yes.
  if (item.module === 'J' && item.variable !== 'SEN_OPTIN') {
    return answers['SEN_OPTIN']?.value === 1
  }
  // Module-E follow-ups display only when their slot holds a selected theme.
  if (/^TOP\d{2}_/.test(item.variable)) {
    return topSlotFilled(item.variable, answers)
  }
  return true
}

/** The chooseable themes for the Module-E slots: the participant's endorsed themes. */
export function selectableThemeLabels(answers: AnswerMap): { stem: string; label: string }[] {
  return endorsedThemeStems(answers).map((stem) => ({ stem, label: themeByStem.get(stem)!.label }))
}

/** Items of a module that are currently displayable, in bank order. */
export function visibleItems(moduleCode: string, allItems: Item[], answers: AnswerMap): Item[] {
  return allItems.filter((i) => i.module === moduleCode && shouldDisplay(i, answers))
}

export { itemsByVar }
