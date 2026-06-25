// Module D: the consensual adult interest matrix — 38 themes × {Appeal, Desire,
// Practice}. Rendered as a compact grid (one theme per row, three dropdowns) per
// the instrument's routing rule. Every cell defaults to unanswered; participants
// may leave any cell blank.

import { themes, scales } from '../instrument/instrument'
import { AnswerValue } from '../instrument/coding'
import { AnswerMap } from './skiplogic'

interface Props {
  answers: AnswerMap
  onChange: (variable: string, value: AnswerValue) => void
}

function Cell({
  variable,
  scaleId,
  value,
  onChange,
}: {
  variable: string
  scaleId: string
  value: AnswerValue
  onChange: (variable: string, value: AnswerValue) => void
}) {
  const opts = scales[scaleId].options
  return (
    <select
      className="matrix-cell"
      value={value === null || value === undefined ? '' : String(value)}
      onChange={(e) => onChange(variable, e.target.value === '' ? null : Number(e.target.value))}
    >
      <option value="">—</option>
      {opts.map((o) => (
        <option key={o.code} value={o.code}>
          {o.code} · {o.label}
        </option>
      ))}
    </select>
  )
}

export default function DMatrix({ answers, onChange }: Props) {
  return (
    <div className="matrix-wrap">
      <table className="matrix">
        <thead>
          <tr>
            <th className="theme-col">Theme</th>
            <th>Appeal</th>
            <th>Desire (legal, consensual adult)</th>
            <th>Consensual adult experience</th>
          </tr>
        </thead>
        <tbody>
          {themes.map((t) => (
            <tr key={t.stem}>
              <td className="theme-col">{t.label}</td>
              <td><Cell variable={t.appeal} scaleId="APPEAL_0_4" value={answers[t.appeal]?.value ?? null} onChange={onChange} /></td>
              <td><Cell variable={t.desire} scaleId="DESIRE_0_4" value={answers[t.desire]?.value ?? null} onChange={onChange} /></td>
              <td><Cell variable={t.practice} scaleId="PRACTICE_0_4" value={answers[t.practice]?.value ?? null} onChange={onChange} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
