// R-SICCI scoring engine — PURE, no DOM, no React.
//
// Input: the participant's answers (value + whether the item was displayed).
// Output: the 10 score-rule results and the data needed for the 9 classification
// axes. Every composite follows the published `score_rules` verbatim, including:
//   • 97/98/99 = MISSING (never zero) — resolved in coding.ts
//   • per-score eligibility gates → return "not computed", never a partial number
//   • reverse coding ONLY where a score_rule says reverse() (CON_PRESSURE for CCS,
//     WB_STRESS for EWI). The item-bank `reverse_coded` flag is the item's
//     intrinsic polarity and is NOT auto-applied to composites — e.g. the SDS
//     rule sums the SOC worry items RAW (higher worry = higher strain).
//   • SRI / Module J are NEVER individually scored or labelled.

import { themes, sensitiveThemes, TOP_THEME_SLOTS } from '../instrument/instrument'
import {
  AnswerValue,
  resolveNumeric,
  reverse,
  meanValid,
  ROLE_MAP,
} from '../instrument/coding'

// ---- Input model ------------------------------------------------------------

export interface AnswerRecord {
  value: AnswerValue
  /** Whether the item was shown to the participant (drives eligibility denominators). */
  displayed: boolean
}

/** Tests/UI may pass either a full record or a bare value (assumed displayed if non-null). */
export type AnswersInput = Record<string, AnswerRecord | AnswerValue>

function record(answers: AnswersInput, v: string): AnswerRecord {
  const a = answers[v]
  if (a !== null && typeof a === 'object' && !Array.isArray(a) && 'value' in a) {
    return a as AnswerRecord
  }
  const value = (a ?? null) as AnswerValue
  return { value, displayed: value !== null && value !== undefined }
}

function value(answers: AnswersInput, v: string): AnswerValue {
  return record(answers, v).value
}

// ---- Result model -----------------------------------------------------------

export interface ScoreResult {
  /** 0–100 composite, or null when the eligibility gate is not met. */
  value: number | null
  eligible: boolean
  /** Count of valid (non-missing) inputs that fed the score. */
  validCount: number
  /** Denominator considered for the eligibility gate. */
  considered: number
  tag: string | null
  note?: string
}

function notComputed(considered: number, validCount: number, note: string): ScoreResult {
  return { value: null, eligible: false, validCount, considered, tag: null, note }
}

// ---- Tag banding ------------------------------------------------------------

function band(value: number, cuts: number[], labels: string[]): string {
  for (let i = 0; i < cuts.length; i++) if (value <= cuts[i]) return labels[i]
  return labels[labels.length - 1]
}

const CII_TAGS = ['Lower disclosed', 'Slight-to-moderate', 'Moderate-to-strong', 'Strong']
const KIS_TAGS = ['Low salience', 'Emerging', 'Connected', 'Highly salient']
const CCS_TAGS = ['Lower self-reported resources', 'Variable/developing', 'Higher self-reported resources']
const DFI_TAGS = ['Limited self-reported impact', 'Some self-reported impact', 'Substantial self-reported impact']
const PRACTICE_TAGS = ['No practice disclosed', 'Past only', 'Recent', 'Occasional', 'Regular']

// ---- Module D: CII, CIB, CAP ------------------------------------------------

interface DMatrixStats {
  cii: ScoreResult
  cib: ScoreResult & { count: number }
  cap: ScoreResult & { maxPracticeCode: number | null }
}

function scoreDMatrix(answers: AnswersInput): DMatrixStats {
  // Appeal/Desire eligibility: ≥70% of *displayed* appeal/desire cells valid.
  let adDisplayed = 0
  let adValid = 0
  let practiceDisplayed = 0
  let practiceValid = 0

  const themeMeans: number[] = [] // themes with ≥1 valid appeal/desire
  const practicePcts: number[] = []
  let maxPracticeCode: number | null = null

  for (const t of themes) {
    const aRec = record(answers, t.appeal)
    const dRec = record(answers, t.desire)
    const pRec = record(answers, t.practice)

    if (aRec.displayed) adDisplayed++
    if (dRec.displayed) adDisplayed++
    const aNum = resolveNumeric(t.appeal, aRec.value)
    const dNum = resolveNumeric(t.desire, dRec.value)
    if (aNum !== null) adValid++
    if (dNum !== null) adValid++

    const themeMean = meanValid([aNum, dNum])
    if (themeMean !== null) themeMeans.push(themeMean)

    if (pRec.displayed) practiceDisplayed++
    const pNum = resolveNumeric(t.practice, pRec.value)
    if (pNum !== null) {
      practiceValid++
      practicePcts.push((pNum / 4) * 100)
      if (maxPracticeCode === null || pNum > maxPracticeCode) maxPracticeCode = pNum
    }
  }

  const adEligible = adDisplayed > 0 && adValid / adDisplayed >= 0.7
  const capEligible = practiceDisplayed > 0 && practiceValid / practiceDisplayed >= 0.7

  // CII
  let cii: ScoreResult
  if (!adEligible) {
    cii = notComputed(adDisplayed, adValid, 'Fewer than 70% of displayed Appeal/Desire cells were valid.')
  } else {
    const meanThemeMean = meanValid(themeMeans)
    if (meanThemeMean === null) {
      cii = notComputed(adDisplayed, adValid, 'No themes with a valid Appeal or Desire response.')
    } else {
      const v = (meanThemeMean / 4) * 100
      cii = { value: v, eligible: true, validCount: adValid, considered: adDisplayed, tag: band(v, [24, 49, 74], CII_TAGS) }
    }
  }

  // CIB
  let cib: ScoreResult & { count: number }
  if (!adEligible) {
    cib = { ...notComputed(adDisplayed, adValid, 'Same gate as CII.'), count: 0 }
  } else {
    const denom = themeMeans.length
    const count = themeMeans.filter((m) => m >= 2.0).length
    const v = denom > 0 ? (count / denom) * 100 : 0
    cib = {
      value: v,
      eligible: true,
      validCount: adValid,
      considered: adDisplayed,
      tag: band(count, [1, 4, 9], ['No/few themes (0–1)', 'Focused (2–4)', 'Multi-theme (5–9)', 'Broad (10+)']),
      count,
    }
  }

  // CAP
  let cap: ScoreResult & { maxPracticeCode: number | null }
  if (!capEligible) {
    cap = { ...notComputed(practiceDisplayed, practiceValid, 'Fewer than 70% of displayed Practice cells were valid.'), maxPracticeCode }
  } else {
    const v = meanValid(practicePcts) ?? 0
    cap = {
      value: v,
      eligible: true,
      validCount: practiceValid,
      considered: practiceDisplayed,
      tag: maxPracticeCode === null ? 'No practice disclosed' : PRACTICE_TAGS[maxPracticeCode] ?? null,
      maxPracticeCode,
    }
  }

  return { cii, cib, cap }
}

// ---- Generic composite: mean of N items / 4 * 100, with an "M of N" gate -----

function composite(
  answers: AnswersInput,
  vars: { variable: string; reverse?: boolean }[],
  minValid: number,
  tags?: { cuts: number[]; labels: string[] },
): ScoreResult {
  const resolved = vars.map((spec) => {
    const n = resolveNumeric(spec.variable, value(answers, spec.variable))
    return spec.reverse ? reverse(n) : n
  })
  const validCount = resolved.filter((v) => v !== null).length
  if (validCount < minValid) {
    return notComputed(vars.length, validCount, `Fewer than ${minValid} of ${vars.length} required items valid.`)
  }
  const m = meanValid(resolved)
  if (m === null) return notComputed(vars.length, validCount, 'No valid items.')
  const v = (m / 4) * 100
  return {
    value: v,
    eligible: true,
    validCount,
    considered: vars.length,
    tag: tags ? band(v, tags.cuts, tags.labels) : null,
  }
}

// Mean of selected-theme (Module E) follow-up values across the five slots.
function topSlotMean(answers: AnswersInput, suffix: string): number | null {
  const vals = TOP_THEME_SLOTS.map((_, i) => {
    const slot = String(i + 1).padStart(2, '0')
    return resolveNumeric(`TOP${slot}${suffix}`, value(answers, `TOP${slot}${suffix}`))
  })
  return meanValid(vals)
}

// ---- SDS and DFI: a core sub-mean averaged with an optional selected-theme sub-mean

function scoreSDS(answers: AnswersInput): ScoreResult {
  // Core: 6 SOC/DFI_SOCIAL items, summed RAW (NOT reversed — see header note).
  const coreVars = [
    'SOC_WORKPLACE_WORRY',
    'SOC_DISCLOSURE_WORRY',
    'SOC_DISCRIMINATION',
    'SOC_HEALTHCARE_AVOID',
    'SOC_ISOLATED',
    'DFI_SOCIAL',
  ]
  const core = coreVars.map((v) => resolveNumeric(v, value(answers, v)))
  const coreValid = core.filter((v) => v !== null).length
  if (coreValid < 5) {
    return notComputed(coreVars.length, coreValid, 'Fewer than 5 of 6 core stigma items valid.')
  }
  const coreMean = meanValid(core)!
  const stigmaMean = topSlotMean(answers, '_STIGMA') // optional add-on
  const combined = stigmaMean === null ? coreMean : (coreMean + stigmaMean) / 2
  return {
    value: (combined / 4) * 100,
    eligible: true,
    validCount: coreValid,
    considered: coreVars.length,
    tag: null, // continuous only; avoid labels in participant view
    note: stigmaMean === null ? undefined : 'Includes selected-theme stigma sub-mean.',
  }
}

function scoreDFI(answers: AnswersInput): ScoreResult & { supportTrigger: boolean } {
  const coreVars = ['DFI_INTRUSIVE', 'DFI_VALUES', 'DFI_FUNCTION', 'DFI_CONTROL', 'DFI_SAFETY']
  const core = coreVars.map((v) => resolveNumeric(v, value(answers, v)))
  const coreValid = core.filter((v) => v !== null).length

  const safety = resolveNumeric('DFI_SAFETY', value(answers, 'DFI_SAFETY'))
  const fn = resolveNumeric('DFI_FUNCTION', value(answers, 'DFI_FUNCTION'))
  const supportTrigger = (safety !== null && safety >= 3) || (fn !== null && fn >= 3)

  if (coreValid < 4) {
    return { ...notComputed(coreVars.length, coreValid, 'Fewer than 4 of 5 core DFI items valid.'), supportTrigger }
  }
  const coreMean = meanValid(core)!
  const posNegMean = topSlotMean(answers, '_POS_NEG') // 0–3 sub-scale, normalized by /4 per rule
  const combined = posNegMean === null ? coreMean : (coreMean + posNegMean) / 2
  const v = (combined / 4) * 100
  return {
    value: v,
    eligible: true,
    validCount: coreValid,
    considered: coreVars.length,
    tag: band(v, [33, 66], DFI_TAGS),
    supportTrigger,
  }
}

// ---- Role orientation (TOP##_ROLE) ------------------------------------------

function roleOrientation(answers: AnswersInput): { tag: string; perSlot: (string | null)[] } {
  const perSlot = TOP_THEME_SLOTS.map((_, i) => {
    const slot = String(i + 1).padStart(2, '0')
    const raw = value(answers, `TOP${slot}_ROLE`)
    return typeof raw === 'string' ? (ROLE_MAP[raw.trim().toLowerCase()] ?? null) : null
  })
  const present = perSlot.filter((r): r is string => r !== null)
  let tag: string
  if (present.length === 0) tag = 'No role preference/not applicable'
  else {
    const distinct = new Set(present)
    tag = distinct.size === 1 ? present[0] : 'Varies'
  }
  return { tag, perSlot }
}

// ---- Consent-experience indicators (CEI): retained raw, no composite --------

function consentExperience(answers: AnswersInput) {
  return {
    CON_LIMIT_CROSSED: value(answers, 'CON_LIMIT_CROSSED'),
    CON_UNABLE_STOP: value(answers, 'CON_UNABLE_STOP'),
    CON_MISUNDERSTOOD: value(answers, 'CON_MISUNDERSTOOD'),
    CON_SUPPORT_SOUGHT: value(answers, 'CON_SUPPORT_SOUGHT'),
  }
}

// ---- SRI: Restricted Sensitive-Theme Research Index -------------------------
//
// Per the instrument, Module J retains thought-frequency, unwantedness, and
// impact for each sensitive theme. This computes an individual, researcher-facing
// SRI index from those items (overall 0–100, plus thought/severity sub-scores, a
// per-theme breakdown, and the prevalence of non-zero thought-frequency).
//
// IMPORTANT — this is a DESCRIPTIVE research index, not a risk, dangerousness, or
// likelihood-of-offending measure, and it is never participant-facing. It must
// not be exposed to recruiters, instructors, payment staff, or app admins. The
// items are thoughts/urges only (no behavior, target, or event).

export interface SensitiveThemeScore {
  stem: string
  label: string
  thought: number | null // frequency 0–4
  unwanted: number | null // distress 0–4
  impact: number | null // distress 0–4
}

export interface SRIResult extends ScoreResult {
  /** Mean thought-frequency as 0–100. */
  thoughtMean: number | null
  /** Mean of unwantedness + impact (distress) as 0–100. */
  severityMean: number | null
  /** Number of themes with thought-frequency ≥ 1. */
  prevalence: number
  /** Whether the participant opted into Module J. */
  optedIn: boolean
  themes: SensitiveThemeScore[]
}

function scoreSRI(answers: AnswersInput, optedIn: boolean): SRIResult {
  const rows: SensitiveThemeScore[] = sensitiveThemes.map((t) => ({
    stem: t.stem,
    label: t.label,
    thought: resolveNumeric(t.thought, value(answers, t.thought)),
    unwanted: resolveNumeric(t.unwanted, value(answers, t.unwanted)),
    impact: resolveNumeric(t.impact, value(answers, t.impact)),
  }))

  const allCells = rows.flatMap((r) => [r.thought, r.unwanted, r.impact])
  const validCount = allCells.filter((v) => v !== null).length
  const prevalence = rows.filter((r) => r.thought !== null && r.thought >= 1).length

  // Optional module, no missingness penalty: compute whenever there is any data.
  if (!optedIn || validCount === 0) {
    return {
      value: null,
      eligible: false,
      validCount,
      considered: allCells.length,
      tag: null,
      note: optedIn ? 'Opted in but no restricted-theme items answered.' : 'Participant did not opt into Module J.',
      thoughtMean: null,
      severityMean: null,
      prevalence,
      optedIn,
      themes: rows,
    }
  }

  const overall = (meanValid(allCells)! / 4) * 100
  const thoughtMean = meanValid(rows.map((r) => r.thought))
  const severityMean = meanValid(rows.flatMap((r) => [r.unwanted, r.impact]))

  return {
    value: overall,
    eligible: true,
    validCount,
    considered: allCells.length,
    // Local descriptive bands (the instrument gives SRI no numeric anchors).
    tag: band(overall, [24, 49, 74], ['Minimal', 'Low', 'Moderate', 'High']) + ' endorsement (descriptive)',
    thoughtMean: thoughtMean === null ? null : (thoughtMean / 4) * 100,
    severityMean: severityMean === null ? null : (severityMean / 4) * 100,
    prevalence,
    optedIn,
    themes: rows,
  }
}

// ---- Top-level scoring ------------------------------------------------------

export interface ScoringOutput {
  cii: ScoreResult
  cib: ScoreResult & { count: number }
  cap: ScoreResult & { maxPracticeCode: number | null }
  kis: ScoreResult
  /** KID_NO_IDENTITY: contextual tag, never scored as concealment/pathology. */
  noIdentityContext: number | null
  ccs: ScoreResult
  cei: ReturnType<typeof consentExperience>
  sds: ScoreResult
  dfi: ScoreResult & { supportTrigger: boolean }
  ewi: ScoreResult
  role: ReturnType<typeof roleOrientation>
  /** Restricted Sensitive-Theme Research Index — researcher-only, descriptive. */
  sri: SRIResult
}

export function score(answers: AnswersInput): ScoringOutput {
  const d = scoreDMatrix(answers)

  const kis = composite(
    answers,
    ['KID_IMPORTANCE', 'KID_COMMUNITY_ONLINE', 'KID_COMMUNITY_INPERSON', 'KID_EDUCATION', 'KID_TRUSTED_PEER', 'KID_PARAPHERNALIA'].map(
      (variable) => ({ variable }),
    ),
    4,
    { cuts: [24, 49, 74], labels: KIS_TAGS },
  )

  const ccs = composite(
    answers,
    [
      { variable: 'CON_NEGOTIATE' },
      { variable: 'CON_STOP' },
      { variable: 'CON_CHANGE_MIND' },
      { variable: 'CON_PARTNER_RESPECT' },
      { variable: 'CON_DECLINE_SAFE' },
      { variable: 'CON_CAPACITY' },
      { variable: 'CON_PRESSURE', reverse: true },
      { variable: 'CON_CHECKIN' },
      { variable: 'CON_AFTERCARE' },
      { variable: 'CON_RECORDING' },
      { variable: 'CON_SUBSTANCE' },
      { variable: 'CON_INFORMATION' },
    ],
    9,
    { cuts: [49, 74], labels: CCS_TAGS },
  )

  const ewi = composite(
    answers,
    [
      { variable: 'WB_LIFE_SAT' },
      { variable: 'WB_ENERGY' },
      { variable: 'WB_CALM' },
      { variable: 'WB_INTEREST' },
      { variable: 'WB_SOCIAL' },
      { variable: 'WB_STRESS', reverse: true },
    ],
    4,
  )

  return {
    cii: d.cii,
    cib: d.cib,
    cap: d.cap,
    kis,
    noIdentityContext: resolveNumeric('KID_NO_IDENTITY', value(answers, 'KID_NO_IDENTITY')),
    ccs,
    cei: consentExperience(answers),
    sds: scoreSDS(answers),
    dfi: scoreDFI(answers),
    ewi,
    role: roleOrientation(answers),
    sri: scoreSRI(answers, value(answers, 'SEN_OPTIN') === 1),
  }
}
