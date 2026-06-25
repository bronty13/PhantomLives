// Dual-mode home screen. One self-contained build serves both roles:
//   • "Take the survey"  → the administration copy (a participant), which exports
//     one data file at the end.
//   • "Score a data file" → the researcher copy, which imports that file and
//     produces the descriptive profile.

import { useState } from 'react'
import instrument from './instrument/instrument'
import Administer from './admin/Administer'
import ScorePage from './score/Report'

type Mode = 'home' | 'administer' | 'score'

export default function App() {
  const [mode, setMode] = useState<Mode>('home')

  if (mode === 'administer') return <Administer onExit={() => setMode('home')} />
  if (mode === 'score') return <ScorePage onExit={() => setMode('home')} />

  return (
    <div className="screen home">
      <h1>{instrument.instrument_name}</h1>
      <p className="version">{instrument.version}</p>
      <p className="muted">{instrument.purpose}</p>

      <div className="mode-cards">
        <button className="mode-card" onClick={() => setMode('administer')}>
          <h2>Take the survey</h2>
          <p>Answer the questionnaire and save your responses to a single file to return to the research team.</p>
        </button>
        <button className="mode-card" onClick={() => setMode('score')}>
          <h2>Score a data file</h2>
          <p>Researcher: import a returned data file to produce the descriptive research profile.</p>
        </button>
      </div>

      <p className="muted small disclaimer">{instrument.administration.no_diagnosis}</p>
    </div>
  )
}
