// The survey runner (administration copy). Pages through the 11 modules in bank
// order, renders Module D as a matrix and Module E as selected-theme follow-ups,
// gates Module J behind its opt-in, terminates on eligibility failure, surfaces
// the optional DFI support screen, and ends on a neutral completion + export —
// never the participant's scores.

import { useEffect, useMemo, useState } from 'react'
import instrument, { items, modules, itemsByVar } from '../instrument/instrument'
import { AnswerValue } from '../instrument/coding'
import { score } from '../score/engine'
import {
  Session,
  newSession,
  loadSession,
  saveSession,
  clearSession,
  setAnswer,
  markDisplayed,
  toPayload,
} from './persistence'
import { AnswerMap, visibleItems, isIneligible, shouldDisplay } from './skiplogic'
import ItemInput from '../components/ItemInput'
import DMatrix from './DMatrix'
import ThemeFollowup from './ThemeFollowup'
import SupportResources from './SupportResources'
import ExportPanel from './ExportPanel'

type Phase = 'intro' | 'module' | 'ineligible' | 'support' | 'complete'

interface Props {
  onExit: () => void
}

export default function Administer({ onExit }: Props) {
  const [session, setSession] = useState<Session | null>(null)
  const [phase, setPhase] = useState<Phase>('intro')
  const [moduleIdx, setModuleIdx] = useState(0)
  const [resuming, setResuming] = useState(false)
  const [supportShown, setSupportShown] = useState(false)

  useEffect(() => {
    const existing = loadSession()
    if (existing) setResuming(true)
  }, [])

  const answers: AnswerMap = session?.answers ?? {}

  function update(next: Session) {
    setSession(next)
    saveSession(next)
  }

  function onChange(variable: string, value: AnswerValue) {
    if (!session) return
    let nextAnswers = setAnswer(session.answers, variable, value)
    const moduleJOptIn = variable === 'SEN_OPTIN' ? value === 1 : session.moduleJOptIn
    update({ ...session, answers: nextAnswers, moduleJOptIn })
  }

  // Mark every currently-visible item in a module as displayed (eligibility denominators).
  function enterModule(s: Session, code: string): Session {
    let a = s.answers
    for (const it of items) {
      if (it.module === code && shouldDisplay(it, a)) a = markDisplayed(a, it.variable)
    }
    return { ...s, answers: a }
  }

  function start() {
    const s = resuming && loadSession() ? loadSession()! : newSession()
    const s2 = enterModule(s, modules[0].code)
    update(s2)
    setModuleIdx(0)
    setPhase('module')
  }

  function restart() {
    clearSession()
    setResuming(false)
    const s = enterModule(newSession(), modules[0].code)
    update(s)
    setModuleIdx(0)
    setPhase('module')
  }

  const dfiTrigger = useMemo(() => (session ? score(session.answers).dfi.supportTrigger : false), [session])

  function next() {
    if (!session) return
    const code = modules[moduleIdx].code
    if (code === 'A' && isIneligible(session.answers)) {
      setPhase('ineligible')
      return
    }
    if (moduleIdx >= modules.length - 1) {
      if (dfiTrigger && !supportShown) {
        setSupportShown(true)
        setPhase('support')
      } else {
        finish()
      }
      return
    }
    const nextCode = modules[moduleIdx + 1].code
    update(enterModule(session, nextCode))
    setModuleIdx(moduleIdx + 1)
    window.scrollTo(0, 0)
  }

  function back() {
    if (moduleIdx > 0) {
      setModuleIdx(moduleIdx - 1)
      window.scrollTo(0, 0)
    }
  }

  function finish() {
    setPhase('complete')
  }

  // ---- Render ----------------------------------------------------------------

  if (phase === 'intro') {
    return (
      <div className="screen intro">
        <button className="link back-top" onClick={onExit}>← Home</button>
        <h1>{instrument.instrument_name}</h1>
        <p className="version">{instrument.version}</p>
        <p>{instrument.administration.preamble}</p>
        <p className="muted">{instrument.administration.no_diagnosis}</p>
        {resuming ? (
          <div className="resume-row">
            <button className="primary" onClick={start}>Resume saved progress</button>
            <button className="link" onClick={restart}>Start over</button>
          </div>
        ) : (
          <button className="primary" onClick={start}>Begin</button>
        )}
      </div>
    )
  }

  if (phase === 'ineligible') {
    return (
      <div className="screen">
        <h2>Thank you</h2>
        <p>This study is open only to adults age 18 and older. Thank you for your time.</p>
        <button className="link" onClick={onExit}>← Home</button>
      </div>
    )
  }

  if (phase === 'support') {
    return <SupportResources onContinue={finish} />
  }

  if (phase === 'complete' && session) {
    return (
      <div className="screen complete">
        <h2>You're finished — thank you</h2>
        <p>
          Your responses are stored only on this device until you save them to a file below. There is
          no score shown here; scoring is done separately by the research team.
        </p>
        <ExportPanel payload={toPayload(session, true)} />
        <p className="muted small">Study ID: {session.studyId}</p>
        <button className="link" onClick={onExit}>← Home</button>
      </div>
    )
  }

  if (!session) return null

  // ---- A module page ---------------------------------------------------------
  const mod = modules[moduleIdx]
  const pct = Math.round(((moduleIdx + 1) / modules.length) * 100)

  return (
    <div className="screen module-page">
      <div className="progress">
        <div className="bar" style={{ width: `${pct}%` }} />
      </div>
      <p className="crumb">
        Section {moduleIdx + 1} of {modules.length} · {mod.estimated_time}
      </p>
      <h2>{mod.name}</h2>
      <p className="muted">{mod.purpose}</p>

      {mod.code === 'D' ? (
        <DMatrix answers={answers} onChange={onChange} />
      ) : mod.code === 'E' ? (
        <ThemeFollowup answers={answers} onChange={onChange} />
      ) : (
        <ModuleItems code={mod.code} answers={answers} onChange={onChange} />
      )}

      <div className="nav">
        <button className="link" onClick={back} disabled={moduleIdx === 0}>← Back</button>
        <button className="primary" onClick={next}>
          {moduleIdx >= modules.length - 1 ? 'Finish' : 'Next →'}
        </button>
      </div>
      <p className="muted small">Progress saves automatically. You can close and resume later.</p>
    </div>
  )
}

function ModuleItems({
  code,
  answers,
  onChange,
}: {
  code: string
  answers: AnswerMap
  onChange: (variable: string, value: AnswerValue) => void
}) {
  const visible = visibleItems(code, items, answers)
  return (
    <div className="items">
      {code === 'J' && (
        <p className="callout">
          The next section is optional and asks only about unwanted thoughts or urges — no behavior,
          no details, no names. You may opt out and it will be skipped entirely.
        </p>
      )}
      {visible.map((item) => {
        // Group D-matrix-style appended labels don't occur here; show the full prompt.
        const sectionLabel = itemsByVar.get(item.variable)?.section
        return (
          <div key={item.variable} className="item">
            {sectionLabel && <p className="section-tag">{sectionLabel}</p>}
            <p className="prompt">{item.participant_prompt}</p>
            <ItemInput item={item} value={answers[item.variable]?.value ?? null} onChange={(v) => onChange(item.variable, v)} />
            <button className="clear-link" onClick={() => onChange(item.variable, null)}>Clear</button>
          </div>
        )
      })}
    </div>
  )
}
