// Scoring & reporting copy (researcher-facing). Imports one data file (encrypted
// or plain), runs the pure scoring engine, and renders the multi-axis descriptive
// profile plus QA flags and the retained — but never individually scored —
// Module J raw values.

import { useState } from 'react'
import { score, ScoringOutput } from './engine'
import { classify, AxisResult } from './classify'
import { loadDataFile, PlainPayload } from '../datafile/datafile'
import { prohibitedUses, items } from '../instrument/instrument'

interface Props {
  onExit: () => void
}

function fmt(v: number | null): string {
  return v === null ? '—' : v.toFixed(1)
}

function ScoreRow({ label, value, tag, note }: { label: string; value: number | null; tag: string | null; note?: string }) {
  return (
    <tr>
      <td className="score-label">{label}</td>
      <td className="score-val">{fmt(value)}</td>
      <td>{tag ?? <span className="muted">—</span>}</td>
      <td className="muted small">{note ?? ''}</td>
    </tr>
  )
}

function AxisCard({ a }: { a: AxisResult }) {
  return (
    <div className="axis-card">
      <h4>{a.axis}</h4>
      <p className="axis-basis muted small">{a.basis}</p>
      <p className="axis-value">
        {a.value !== null && <span className="big">{a.value.toFixed(1)}</span>}
        {a.tag && <span className="axis-tag">{a.tag}</span>}
        {a.value === null && !a.tag && <span className="muted">not computed</span>}
      </p>
      {a.note && <p className="muted small">{a.note}</p>}
    </div>
  )
}

export function Report({ payload }: { payload: PlainPayload }) {
  const s: ScoringOutput = score(payload.answers)
  const axes = classify(s)
  const moduleJVars = items.filter((i) => i.module === 'J').map((i) => i.variable)
  const moduleJAnswered = moduleJVars.filter((v) => payload.answers[v]?.value != null)

  return (
    <div className="report">
      <header className="report-head">
        <div>
          <h2>Descriptive research profile</h2>
          <p className="muted small">
            Study ID <code>{payload.studyId}</code> · {payload.instrumentVersion} · method{' '}
            {payload.methodCondition}
          </p>
        </div>
      </header>

      <section>
        <h3>Scores</h3>
        <table className="scores">
          <thead>
            <tr><th>Score</th><th>0–100</th><th>Band</th><th>Notes</th></tr>
          </thead>
          <tbody>
            <ScoreRow label="CII — Consensual Interest Intensity" value={s.cii.value} tag={s.cii.tag} note={s.cii.note} />
            <ScoreRow label={`CIB — Interest Breadth (${s.cib.count} themes ≥ 2.0)`} value={s.cib.value} tag={s.cib.tag} note={s.cib.note} />
            <ScoreRow label="CAP — Consensual Adult Participation" value={s.cap.value} tag={s.cap.tag} note={s.cap.note} />
            <ScoreRow label="KIS — Identity / Community Salience" value={s.kis.value} tag={s.kis.tag} note={s.kis.note} />
            <ScoreRow label="CCS — Consent-Communication Resources" value={s.ccs.value} tag={s.ccs.tag} note={s.ccs.note} />
            <ScoreRow label="SDS — Stigma / Disclosure Strain" value={s.sds.value} tag={null} note={s.sds.note} />
            <ScoreRow label="DFI — Intrinsic Distress / Functional Impact" value={s.dfi.value} tag={s.dfi.tag} note={s.dfi.note} />
            <ScoreRow label="EWI — Exploratory Wellbeing Index" value={s.ewi.value} tag={null} note={s.ewi.eligible ? undefined : s.ewi.note} />
          </tbody>
        </table>
        {s.dfi.supportTrigger && (
          <p className="callout">
            DFI safety/function trigger met during administration — the participant was shown the
            optional support-resources screen. This is a research signal, not a clinical or legal
            conclusion.
          </p>
        )}
      </section>

      <section>
        <h3>CEI — Consent Experience Indicators (retained separately, no composite)</h3>
        <ul className="cei">
          <li>Limit crossed: <code>{String(s.cei.CON_LIMIT_CROSSED ?? '—')}</code></li>
          <li>Unable to stop: <code>{String(s.cei.CON_UNABLE_STOP ?? '—')}</code></li>
          <li>Misunderstood: <code>{String(s.cei.CON_MISUNDERSTOOD ?? '—')}</code></li>
          <li>Support sought: <code>{String(s.cei.CON_SUPPORT_SOUGHT ?? '—')}</code></li>
        </ul>
      </section>

      <section>
        <h3>Classification profile (9 axes)</h3>
        <div className="axes-grid">
          {axes.map((a) => <AxisCard key={a.axis} a={a} />)}
        </div>
      </section>

      <section>
        <h3>Module J — restricted</h3>
        <p className="muted">
          Opt-in: <strong>{payload.moduleJOptIn ? 'yes' : 'no'}</strong>. {moduleJAnswered.length} of{' '}
          {moduleJVars.length} restricted items answered. Per the instrument, Module J is retained as
          raw research data only and is <strong>never</strong> turned into an individual SRI score,
          label, or profile axis.
        </p>
      </section>

      <section className="qa">
        <h3>Quality flags (for sensitivity analysis, not exclusion)</h3>
        <ul>
          <li>Attention check: <code>{String(payload.qa.attention ?? '—')}</code></li>
          <li>Total time: {payload.qa.totalMs ? `${Math.round(payload.qa.totalMs / 60000)} min` : '—'}</li>
        </ul>
      </section>

      <details className="prohibited">
        <summary>Prohibited uses (read me)</summary>
        <ul>{prohibitedUses.map((p) => <li key={p}>{p}</li>)}</ul>
      </details>
    </div>
  )
}

export default function ScorePage({ onExit }: Props) {
  const [payload, setPayload] = useState<PlainPayload | null>(null)
  const [needsPass, setNeedsPass] = useState<((p: string) => Promise<PlainPayload>) | null>(null)
  const [pass, setPass] = useState('')
  const [error, setError] = useState('')

  async function onFile(file: File) {
    setError('')
    setPayload(null)
    setNeedsPass(null)
    try {
      const text = await file.text()
      const res = loadDataFile(text)
      if (res.encrypted) {
        setNeedsPass(() => res.decrypt!)
      } else {
        setPayload(res.payload!)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function decrypt() {
    if (!needsPass) return
    setError('')
    try {
      setPayload(await needsPass(pass))
      setNeedsPass(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  if (payload) {
    return (
      <div className="screen wide">
        <button className="link back-top" onClick={onExit}>← Home</button>
        <Report payload={payload} />
      </div>
    )
  }

  return (
    <div className="screen">
      <button className="link back-top" onClick={onExit}>← Home</button>
      <h1>Score a data file</h1>
      <p className="muted">
        Import a participant's <code>.rsicci</code> (encrypted) or <code>.json</code> (plain) file to
        produce the descriptive research profile. Files are processed entirely on this device.
      </p>

      <input
        type="file"
        accept=".rsicci,.json,application/json"
        onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])}
      />

      {needsPass && (
        <div className="passfields">
          <p>This file is password-protected. Enter the passphrase the participant used:</p>
          <input type="password" placeholder="Passphrase" value={pass} onChange={(e) => setPass(e.target.value)} />
          <button className="primary" onClick={decrypt}>Decrypt &amp; score</button>
        </div>
      )}

      {error && <p className="error">{error}</p>}
    </div>
  )
}
