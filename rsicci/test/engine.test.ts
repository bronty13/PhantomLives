import { describe, it, expect } from 'vitest'
import { score, AnswersInput, AnswerRecord } from '../src/score/engine'
import { classify } from '../src/score/classify'
import { themes } from '../src/instrument/instrument'
import { resolveNumeric } from '../src/instrument/coding'

const shown = (value: AnswerRecord['value']): AnswerRecord => ({ value, displayed: true })

// Build a Module-D answer set from the first N themes with explicit appeal/desire/practice.
function dMatrix(rows: { appeal: number; desire: number; practice: number }[]): AnswersInput {
  const a: AnswersInput = {}
  rows.forEach((r, i) => {
    const t = themes[i]
    a[t.appeal] = shown(r.appeal)
    a[t.desire] = shown(r.desire)
    a[t.practice] = shown(r.practice)
  })
  return a
}

describe('Module D — CII / CIB / CAP (xlsx worked example)', () => {
  // From the spec's "Scoring Example" sheet (fictional values):
  //   Theme: Appeal, Desire, Practice
  //   A: 3,4,3   B: 2,1,0   C: 0,0,0   D: 4,3,4   E: 1,2,1
  // Expected: CII = 50, CIB count = 2, CAP = 40, max practice = 4.
  const answers = dMatrix([
    { appeal: 3, desire: 4, practice: 3 },
    { appeal: 2, desire: 1, practice: 0 },
    { appeal: 0, desire: 0, practice: 0 },
    { appeal: 4, desire: 3, practice: 4 },
    { appeal: 1, desire: 2, practice: 1 },
  ])
  const s = score(answers)

  it('CII = 50', () => {
    expect(s.cii.eligible).toBe(true)
    expect(s.cii.value).toBeCloseTo(50, 6)
  })
  it('CIB count = 2, percent = 40', () => {
    expect(s.cib.count).toBe(2)
    expect(s.cib.value).toBeCloseTo(40, 6)
    expect(s.cib.tag).toBe('Focused (2–4)')
  })
  it('CAP = 40, max practice code = 4', () => {
    expect(s.cap.value).toBeCloseTo(40, 6)
    expect(s.cap.maxPracticeCode).toBe(4)
    expect(s.cap.tag).toBe('Regular')
  })
})

describe('Module D — per-theme breakdown (parallels SRI)', () => {
  const answers = dMatrix([
    { appeal: 3, desire: 4, practice: 3 },
    { appeal: 2, desire: 1, practice: 0 },
    { appeal: 0, desire: 0, practice: 0 },
  ])
  const s = score(answers)

  it('emits one row per theme with raw cells and derived fields', () => {
    expect(s.themeBreakdown.length).toBe(themes.length)
    const t0 = s.themeBreakdown[0]
    expect(t0.appeal).toBe(3)
    expect(t0.desire).toBe(4)
    expect(t0.practice).toBe(3)
    expect(t0.interestMean).toBeCloseTo(3.5, 6)
    expect(t0.interestPct).toBeCloseTo(87.5, 6)
    expect(t0.meetsBreadth).toBe(true)
    expect(t0.endorsed).toBe(true)
  })

  it('flags non-breadth and non-endorsed themes correctly', () => {
    expect(s.themeBreakdown[1].meetsBreadth).toBe(false) // mean 1.5
    expect(s.themeBreakdown[1].endorsed).toBe(true) // appeal 2
    expect(s.themeBreakdown[2].endorsed).toBe(false) // all zero
    expect(s.themeBreakdown[2].meetsBreadth).toBe(false)
  })

  it('leaves unanswered themes as null cells', () => {
    const last = s.themeBreakdown[themes.length - 1]
    expect(last.appeal).toBeNull()
    expect(last.interestMean).toBeNull()
    expect(last.endorsed).toBe(false)
  })

  it('breadth-flagged count matches CIB count', () => {
    expect(s.themeBreakdown.filter((r) => r.meetsBreadth).length).toBe(s.cib.count)
  })
})

describe('Missing codes (97/98/99) are excluded, not zero', () => {
  it('a 99 is dropped from a theme mean instead of pulling it toward 0', () => {
    // Target theme: appeal=4, desire=99 (PNTA) → theme mean = 4 (not 2).
    // Three more fully-valid themes keep the 70% eligibility gate satisfied
    // (7 of 8 appeal/desire cells valid = 87.5%). All theme means = 4 → CII 100.
    const a: AnswersInput = {}
    const t0 = themes[0]
    a[t0.appeal] = shown(4)
    a[t0.desire] = shown(99)
    for (let i = 1; i < 4; i++) {
      a[themes[i].appeal] = shown(4)
      a[themes[i].desire] = shown(4)
    }
    const s = score(a)
    expect(s.cii.eligible).toBe(true)
    expect(s.cii.value).toBeCloseTo(100, 6)
  })

  it('a displayed-but-missing cell still counts toward the 70% eligibility gate', () => {
    // 4 themes displayed (8 appeal/desire cells); 3 of 8 valid → 37.5% < 70% → not computed.
    const a: AnswersInput = {}
    for (let i = 0; i < 4; i++) {
      const t = themes[i]
      a[t.appeal] = shown(i === 0 ? 3 : 99)
      a[t.desire] = shown(i === 0 ? 3 : i === 1 ? 2 : 99)
    }
    const s = score(a)
    expect(s.cii.eligible).toBe(false)
    expect(s.cii.value).toBeNull()
  })
})

describe('Reverse coding follows the score_rules, not the item-bank flag', () => {
  it('CCS reverses CON_PRESSURE only', () => {
    // All 12 CCS items = 4, except CON_PRESSURE = 0. Reversed pressure = 4, so mean = 4 → 100.
    const vars = [
      'CON_NEGOTIATE', 'CON_STOP', 'CON_CHANGE_MIND', 'CON_PARTNER_RESPECT', 'CON_DECLINE_SAFE',
      'CON_CAPACITY', 'CON_CHECKIN', 'CON_AFTERCARE', 'CON_RECORDING', 'CON_SUBSTANCE', 'CON_INFORMATION',
    ]
    const a: AnswersInput = { CON_PRESSURE: shown(0) }
    vars.forEach((v) => (a[v] = shown(4)))
    const s = score(a)
    expect(s.ccs.value).toBeCloseTo(100, 6)
  })

  it('SDS sums the SOC worry items RAW (high worry = high strain, not reversed)', () => {
    // All 6 core = 4 → coreMean 4 → 100. If they were wrongly reversed, this would be 0.
    const a: AnswersInput = {
      SOC_WORKPLACE_WORRY: shown(4), SOC_DISCLOSURE_WORRY: shown(4), SOC_DISCRIMINATION: shown(4),
      SOC_HEALTHCARE_AVOID: shown(4), SOC_ISOLATED: shown(4), DFI_SOCIAL: shown(4),
    }
    const s = score(a)
    expect(s.sds.value).toBeCloseTo(100, 6)
  })

  it('EWI reverses WB_STRESS only', () => {
    // life-sat 10 (→4), four 0–4 items =4, stress=0 (reversed →4): mean 4 → 100.
    const a: AnswersInput = {
      WB_LIFE_SAT: shown(10), WB_ENERGY: shown(4), WB_CALM: shown(4),
      WB_INTEREST: shown(4), WB_SOCIAL: shown(4), WB_STRESS: shown(0),
    }
    const s = score(a)
    expect(s.ewi.value).toBeCloseTo(100, 6)
  })
})

describe('Eligibility gates return "not computed", never a partial number', () => {
  it('KIS needs ≥4 of 6 valid', () => {
    const a: AnswersInput = { KID_IMPORTANCE: shown(4), KID_COMMUNITY_ONLINE: shown(4), KID_COMMUNITY_INPERSON: shown(4) }
    expect(score(a).kis.value).toBeNull()
    a.KID_EDUCATION = shown(4)
    expect(score(a).kis.value).toBeCloseTo(100, 6)
  })
  it('CCS needs ≥9 of 12 valid', () => {
    const a: AnswersInput = {}
    ;['CON_NEGOTIATE', 'CON_STOP', 'CON_CHANGE_MIND', 'CON_PARTNER_RESPECT', 'CON_DECLINE_SAFE', 'CON_CAPACITY', 'CON_CHECKIN', 'CON_AFTERCARE'].forEach((v) => (a[v] = shown(2)))
    expect(score(a).ccs.value).toBeNull() // only 8 valid
    a.CON_RECORDING = shown(2)
    expect(score(a).ccs.eligible).toBe(true) // 9 valid
  })
})

describe('SINGLE-input coding maps', () => {
  it('WB_LIFE_SAT 0–10 normalizes to 0–4', () => {
    expect(resolveNumeric('WB_LIFE_SAT', 0)).toBe(0)
    expect(resolveNumeric('WB_LIFE_SAT', 5)).toBe(2)
    expect(resolveNumeric('WB_LIFE_SAT', 10)).toBe(4)
  })
  it('TOP01_POS_NEG maps difficulty levels; unsure/PNTA are missing', () => {
    expect(resolveNumeric('TOP01_POS_NEG', 'No')).toBe(0)
    expect(resolveNumeric('TOP01_POS_NEG', 'yes, substantial difficulty')).toBe(3)
    expect(resolveNumeric('TOP01_POS_NEG', 'unsure')).toBeNull()
    expect(resolveNumeric('TOP01_POS_NEG', 'prefer not to answer')).toBeNull()
  })
  it('TOP01_STIGMA maps the 5-point scale', () => {
    expect(resolveNumeric('TOP01_STIGMA', 'Not at all')).toBe(0)
    expect(resolveNumeric('TOP01_STIGMA', 'extremely')).toBe(4)
  })
})

describe('Selected-theme (Module E) contributions', () => {
  it('DFI safety trigger fires when DFI_SAFETY ≥ 3 or DFI_FUNCTION ≥ 3', () => {
    const a: AnswersInput = { DFI_INTRUSIVE: shown(0), DFI_VALUES: shown(0), DFI_FUNCTION: shown(0), DFI_CONTROL: shown(0), DFI_SAFETY: shown(3) }
    expect(score(a).dfi.supportTrigger).toBe(true)
    const b: AnswersInput = { DFI_INTRUSIVE: shown(0), DFI_VALUES: shown(0), DFI_FUNCTION: shown(1), DFI_CONTROL: shown(0), DFI_SAFETY: shown(1) }
    expect(score(b).dfi.supportTrigger).toBe(false)
  })

  it('role orientation summarizes across slots (single → that role, multiple → Varies)', () => {
    expect(score({ TOP01_ROLE: shown('mostly leading/giving') }).role.tag).toBe('Leading/giving')
    expect(
      score({ TOP01_ROLE: shown('mostly leading/giving'), TOP02_ROLE: shown('mostly receiving/following') }).role.tag,
    ).toBe('Varies')
    expect(score({}).role.tag).toBe('No role preference/not applicable')
  })

  it('SDS folds in the selected-theme stigma sub-mean', () => {
    // core all 0 → coreMean 0; one stigma = extremely (4). combined = (0+4)/2 = 2 → 50.
    const a: AnswersInput = {
      SOC_WORKPLACE_WORRY: shown(0), SOC_DISCLOSURE_WORRY: shown(0), SOC_DISCRIMINATION: shown(0),
      SOC_HEALTHCARE_AVOID: shown(0), SOC_ISOLATED: shown(0), DFI_SOCIAL: shown(0),
      TOP01_STIGMA: shown('extremely'),
    }
    expect(score(a).sds.value).toBeCloseTo(50, 6)
  })
})

describe('SRI — Restricted Sensitive-Theme Research Index', () => {
  it('is not computed unless the participant opted into Module J', () => {
    // Answers present but no opt-in → not computed.
    const a: AnswersInput = { SEN_ANIMALS_THOUGHT: shown(2), SEN_ANIMALS_UNWANTED: shown(2), SEN_ANIMALS_IMPACT: shown(2) }
    const s = score(a)
    expect(s.sri.eligible).toBe(false)
    expect(s.sri.value).toBeNull()
    expect(s.sri.optedIn).toBe(false)
  })

  it('computes an overall index, sub-scores, and prevalence when opted in', () => {
    const a: AnswersInput = {
      SEN_OPTIN: shown(1),
      // theme 1: all 4s → contributes 4,4,4
      SEN_ANIMALS_THOUGHT: shown(4), SEN_ANIMALS_UNWANTED: shown(4), SEN_ANIMALS_IMPACT: shown(4),
      // theme 2: thought 0 (no prevalence), severity 2s
      SEN_BELOW_LEGAL_AGE_THOUGHT: shown(0), SEN_BELOW_LEGAL_AGE_UNWANTED: shown(2), SEN_BELOW_LEGAL_AGE_IMPACT: shown(2),
    }
    const s = score(a)
    expect(s.sri.eligible).toBe(true)
    // 6 valid cells: 4,4,4,0,2,2 → mean 16/6 = 2.667 → /4*100 = 66.67
    expect(s.sri.value).toBeCloseTo((16 / 6 / 4) * 100, 4)
    // thought mean: (4+0)/2 = 2 → 50
    expect(s.sri.thoughtMean).toBeCloseTo(50, 6)
    // severity mean: (4+4+2+2)/4 = 3 → 75
    expect(s.sri.severityMean).toBeCloseTo(75, 6)
    expect(s.sri.prevalence).toBe(1) // only theme 1 has thought ≥ 1
    expect(s.sri.tag).toMatch(/descriptive/i)
  })

  it('classify() presents the SRI axis as a researcher-only, non-risk index', () => {
    const a: AnswersInput = { SEN_OPTIN: shown(1), SEN_ANIMALS_THOUGHT: shown(3), SEN_ANIMALS_UNWANTED: shown(1), SEN_ANIMALS_IMPACT: shown(1) }
    const axis = classify(score(a)).find((x) => x.basis === 'SRI')!
    expect(axis.value).not.toBeNull()
    expect(axis.note).toMatch(/not a risk|researcher-access/i)
  })
})
