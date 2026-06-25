// Module E: up to five personally relevant themes. The participant picks a theme
// for each slot (only themes they endorsed ≥1 in Module D are offered), and each
// filled slot reveals its seven follow-up items (TOP0N_AWARENESS … _STIGMA).

import { itemsByVar, TOP_THEME_SLOTS, TOP_FOLLOWUP_SUFFIXES, themeByStem } from '../instrument/instrument'
import { AnswerValue } from '../instrument/coding'
import { AnswerMap, selectableThemeLabels } from './skiplogic'
import ItemInput from '../components/ItemInput'

interface Props {
  answers: AnswerMap
  onChange: (variable: string, value: AnswerValue) => void
}

export default function ThemeFollowup({ answers, onChange }: Props) {
  const choices = selectableThemeLabels(answers)

  if (choices.length === 0) {
    return (
      <p className="muted">
        No themes were endorsed in the previous section, so there are no selected-theme follow-ups.
        You can continue.
      </p>
    )
  }

  return (
    <div>
      <p className="muted">
        Select up to five themes that are most relevant to you right now. For each one you choose,
        a few short follow-up questions will appear.
      </p>
      {TOP_THEME_SLOTS.map((slotVar, idx) => {
        const slot = String(idx + 1).padStart(2, '0')
        const chosen = (answers[slotVar]?.value as string | undefined) ?? ''
        const chosenLabel =
          chosen && themeByStem.has(chosen) ? themeByStem.get(chosen)!.label : ''
        const filled = chosenLabel !== ''
        return (
          <fieldset key={slotVar} className="slot">
            <legend>Theme slot {idx + 1}</legend>
            <select
              value={chosen}
              onChange={(e) => onChange(slotVar, e.target.value === '' ? null : e.target.value)}
            >
              <option value="">No additional theme</option>
              {choices.map((c) => (
                <option key={c.stem} value={c.stem}>
                  {c.label}
                </option>
              ))}
            </select>

            {filled && (
              <div className="followups">
                <p className="context">Follow-up about: <strong>{chosenLabel}</strong></p>
                {TOP_FOLLOWUP_SUFFIXES.map((suf) => {
                  const v = `TOP${slot}${suf}`
                  const item = itemsByVar.get(v)
                  if (!item) return null
                  return (
                    <div key={v} className="item">
                      <p className="prompt">{item.participant_prompt}</p>
                      <ItemInput item={item} value={answers[v]?.value ?? null} onChange={(val) => onChange(v, val)} />
                    </div>
                  )
                })}
              </div>
            )}
          </fieldset>
        )
      })}
    </div>
  )
}
