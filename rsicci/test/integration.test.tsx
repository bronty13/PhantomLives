// End-to-end data path + headless render smoke test.
//
// The browser extension was unavailable for live UI driving, so this proves the
// full pipeline another way: build a realistic answer set → score → export
// (encrypted) → reload + decrypt → re-score (identical) → render the researcher
// Report and App to static HTML (proving the React components mount and surface
// the computed numbers without a runtime crash).

import { describe, it, expect } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import { createElement } from 'react'
import App from '../src/App'
import { Report } from '../src/score/Report'
import Administer from '../src/admin/Administer'
import DMatrix from '../src/admin/DMatrix'
import ThemeFollowup from '../src/admin/ThemeFollowup'
import SupportResources from '../src/admin/SupportResources'
import ExportPanel from '../src/admin/ExportPanel'
import { score } from '../src/score/engine'
import { themes } from '../src/instrument/instrument'
import { PlainPayload, StoredAnswer, encryptPayload, loadDataFile } from '../src/datafile/datafile'

const shown = (value: StoredAnswer['value']): StoredAnswer => ({ value, displayed: true })

function buildPayload(): PlainPayload {
  const answers: Record<string, StoredAnswer> = {}
  // xlsx worked example: 5 themes → CII 50, CIB 2, CAP 40.
  ;[
    { a: 3, d: 4, p: 3 },
    { a: 2, d: 1, p: 0 },
    { a: 0, d: 0, p: 0 },
    { a: 4, d: 3, p: 4 },
    { a: 1, d: 2, p: 1 },
  ].forEach((r, i) => {
    const t = themes[i]
    answers[t.appeal] = shown(r.a)
    answers[t.desire] = shown(r.d)
    answers[t.practice] = shown(r.p)
  })
  // Enough KIS + CCS to compute those too.
  ;['KID_IMPORTANCE', 'KID_COMMUNITY_ONLINE', 'KID_COMMUNITY_INPERSON', 'KID_EDUCATION'].forEach((v) => (answers[v] = shown(3)))
  ;['CON_NEGOTIATE', 'CON_STOP', 'CON_CHANGE_MIND', 'CON_PARTNER_RESPECT', 'CON_DECLINE_SAFE', 'CON_CAPACITY', 'CON_CHECKIN', 'CON_AFTERCARE', 'CON_RECORDING'].forEach((v) => (answers[v] = shown(4)))
  answers['CON_PRESSURE'] = shown(0)
  return {
    format: 'rsicci-plain-1',
    instrumentVersion: 'Draft v0.1',
    studyId: 'E2E001',
    methodCondition: 'wording-A',
    startedAt: 0,
    completedAt: 1000,
    moduleJOptIn: false,
    answers,
    qa: { totalMs: 1000 },
  }
}

describe('full data path: score → encrypt → reload → decrypt → re-score', () => {
  it('round-trips and produces identical scores', async () => {
    const payload = buildPayload()
    const first = score(payload.answers)
    expect(first.cii.value).toBeCloseTo(50, 6)

    const enc = await encryptPayload(payload, 'study-pass-123')
    const loaded = loadDataFile(JSON.stringify(enc))
    expect(loaded.encrypted).toBe(true)
    const back = await loaded.decrypt!('study-pass-123')

    const second = score(back.answers)
    expect(second.cii.value).toBeCloseTo(first.cii.value!, 9)
    expect(second.cib.count).toBe(first.cib.count)
    expect(second.cap.value).toBeCloseTo(first.cap.value!, 9)
    expect(second.ccs.value).toBeCloseTo(100, 6) // pressure reversed
  })
})

describe('headless render smoke test', () => {
  it('App renders the home screen', () => {
    const html = renderToStaticMarkup(createElement(App))
    expect(html).toContain('Take the survey')
    expect(html).toContain('Score a data file')
    expect(html).toMatch(/R-SICCI|Sexual Interests/)
  })

  it('Report renders with computed scores and the SRI-withheld notice', () => {
    const html = renderToStaticMarkup(createElement(Report, { payload: buildPayload() }))
    expect(html).toContain('Descriptive research profile')
    expect(html).toContain('50.0') // CII
    expect(html).toContain('Focused (2–4)') // CIB band
    expect(html).toContain('Restricted Sensitive-Theme Research Index') // SRI section present
    expect(html).toMatch(/risk, dangerousness/i) // SRI misuse guardrail kept
    expect(html).toContain('Prohibited uses')
  })

  it('Report renders the populated SRI breakdown when Module J was opted into', () => {
    const payload = buildPayload()
    payload.moduleJOptIn = true
    payload.answers['SEN_OPTIN'] = shown(1)
    payload.answers['SEN_ANIMALS_THOUGHT'] = shown(2)
    payload.answers['SEN_ANIMALS_UNWANTED'] = shown(3)
    payload.answers['SEN_ANIMALS_IMPACT'] = shown(1)
    const html = renderToStaticMarkup(createElement(Report, { payload }))
    expect(html).toContain('SRI — overall index')
    expect(html).toContain('Thought-frequency sub-score')
    expect(html).toMatch(/prevalence \d+\/8/)
  })

  // The home-only App render leaves the whole admin UI unexercised; render the
  // complex admin components directly so render-time crashes can't ship blind.
  const noop = () => {}

  it('Administer mounts (intro screen)', () => {
    const html = renderToStaticMarkup(createElement(Administer, { onExit: noop }))
    expect(html).toMatch(/Begin|Resume/)
  })

  it('DMatrix renders all 38 theme rows with three dropdowns each', () => {
    const html = renderToStaticMarkup(createElement(DMatrix, { answers: {}, onChange: noop }))
    expect(html).toContain('Appeal')
    // 38 themes × 3 cells = 114 <select> controls.
    expect((html.match(/<select/g) || []).length).toBe(themes.length * 3)
  })

  it('ThemeFollowup reveals follow-ups for an endorsed, selected theme', () => {
    const answers: Record<string, StoredAnswer> = {
      [themes[0].appeal]: shown(3), // endorses theme 0
      TOP_THEME_01: shown(themes[0].stem), // selects it into slot 1
    }
    const html = renderToStaticMarkup(createElement(ThemeFollowup, { answers, onChange: noop }))
    expect(html).toContain('Follow-up about:')
    expect(html).toContain(themes[0].label)
  })

  it('SupportResources and ExportPanel render without crashing', () => {
    expect(renderToStaticMarkup(createElement(SupportResources, { onContinue: noop }))).toContain('resources')
    expect(renderToStaticMarkup(createElement(ExportPanel, { payload: buildPayload() }))).toContain('data file')
  })
})
