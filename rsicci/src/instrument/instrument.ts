// Typed loader for the embedded R-SICCI item bank.
//
// The instrument JSON (rsicci_draft_v0_1.json) is the canonical, machine-readable
// definition of the survey: every item, the response scales, the 10 score rules,
// and the 9 classification axes. We embed it (resolveJsonModule) so the built SPA
// is a single self-contained file with no external fetch.

import raw from './rsicci_draft_v0_1.json'

// ---- Raw shapes (as they appear in the JSON) --------------------------------

export type ResponseTypeId =
  | 'APPEAL_0_4'
  | 'DESIRE_0_4'
  | 'PRACTICE_0_4'
  | 'AGREE_0_4'
  | 'FREQUENCY_0_4'
  | 'IMPACT_0_4'
  | 'DISTRESS_0_4'
  | 'YES_NO_SKIP'
  | 'MULTI'
  | 'TEXT'
  | 'SINGLE'

export interface Item {
  module: string
  variable: string
  section: string
  participant_prompt: string
  response_type: ResponseTypeId
  response_options: string
  required: string
  skip_logic: string
  scoring_domain: string
  reverse_coded: 'Yes' | 'No'
  sensitivity: string
  rationale: string
  developer_notes: string
}

export interface ScaleOption {
  code: number
  label: string
}

export interface Scale {
  label: string
  options: ScaleOption[]
}

export interface ModuleDef {
  code: string
  name: string
  estimated_time: string
  purpose: string
}

export interface ScoreRule {
  score: string
  inputs: string
  eligibility: string
  use: string
  interpretation?: string
}

export interface ProfileAxis {
  axis: string
  basis: string
  tags: string[]
}

interface Instrument {
  instrument_name: string
  version: string
  purpose: string
  administration: Record<string, string>
  modules: ModuleDef[]
  scales: Record<string, { label: string; options: [number, string][] }>
  items: Item[]
  score_rules: ScoreRule[]
  classification: {
    purpose: string
    completeness: string
    profile_axes: ProfileAxis[]
    prohibited_uses: string[]
  }
  implementation: {
    routing: string[]
    data_separation: string[]
    quality: string[]
  }
  references: { citation: string; url: string }[]
}

const instrument = raw as unknown as Instrument

export default instrument
export const INSTRUMENT_VERSION = instrument.version

// ---- Indexed access ---------------------------------------------------------

export const items: Item[] = instrument.items
export const itemsByVar: Map<string, Item> = new Map(items.map((i) => [i.variable, i]))
export const modules: ModuleDef[] = instrument.modules
export const scoreRules: ScoreRule[] = instrument.score_rules
export const profileAxes: ProfileAxis[] = instrument.classification.profile_axes
export const prohibitedUses: string[] = instrument.classification.prohibited_uses

/** Scales as `{ id -> { label, options:[{code,label}] } }`. */
export const scales: Record<string, Scale> = Object.fromEntries(
  Object.entries(instrument.scales).map(([id, s]) => [
    id,
    { label: s.label, options: s.options.map(([code, label]) => ({ code, label })) },
  ]),
)

/** The 0–4 ordinal coded scales whose 97/98/99 codes mean "missing", not zero. */
export const CODED_SCALES = new Set<ResponseTypeId>([
  'APPEAL_0_4',
  'DESIRE_0_4',
  'PRACTICE_0_4',
  'AGREE_0_4',
  'FREQUENCY_0_4',
  'IMPACT_0_4',
  'DISTRESS_0_4',
  'YES_NO_SKIP',
])

/** Split a SINGLE/MULTI item's `response_options` string into labelled choices. */
export function parseChoiceOptions(item: Item): string[] {
  return item.response_options
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean)
}

// ---- Module D theme model ---------------------------------------------------
//
// Module D is a matrix: 38 themes × {Appeal, Desire, Practice}. Each theme has
// three items named INT_<STEM>_APPEAL / _DESIRE / _PRACTICE. The participant-
// facing theme label is the trailing clause of the APPEAL prompt (after the
// standard question stem and its "?").

export interface Theme {
  stem: string // e.g. INT_ADULT_HUMILIATION
  label: string // human-readable theme description
  appeal: string // variable name
  desire: string
  practice: string
}

function themeLabelFromPrompt(prompt: string): string {
  const q = prompt.indexOf('? ')
  return q >= 0 ? prompt.slice(q + 2).trim() : prompt.trim()
}

export const themes: Theme[] = items
  .filter((i) => i.module === 'D' && i.variable.endsWith('_APPEAL'))
  .map((appealItem) => {
    const stem = appealItem.variable.replace(/_APPEAL$/, '')
    return {
      stem,
      label: themeLabelFromPrompt(appealItem.participant_prompt),
      appeal: `${stem}_APPEAL`,
      desire: `${stem}_DESIRE`,
      practice: `${stem}_PRACTICE`,
    }
  })

export const themeByStem: Map<string, Theme> = new Map(themes.map((t) => [t.stem, t]))

/** The five Module-E theme slots, in order. */
export const TOP_THEME_SLOTS = ['TOP_THEME_01', 'TOP_THEME_02', 'TOP_THEME_03', 'TOP_THEME_04', 'TOP_THEME_05']

/** Module-E follow-up variable suffixes attached to each chosen slot. */
export const TOP_FOLLOWUP_SUFFIXES = [
  '_AWARENESS',
  '_DISCLOSURE',
  '_NEGOTIATION',
  '_POS_NEG',
  '_ROLE',
  '_STABILITY',
  '_STIGMA',
]
