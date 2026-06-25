// Renders the appropriate control for a single survey item based on its
// response type. Skipping is always allowed: every item shows a "Skip / prefer
// not to answer" affordance and nothing forces a response to advance.

import { Item, scales, parseChoiceOptions } from '../instrument/instrument'
import { AnswerValue } from '../instrument/coding'

interface Props {
  item: Item
  value: AnswerValue
  onChange: (value: AnswerValue) => void
}

function Radio({
  name,
  options,
  value,
  onChange,
}: {
  name: string
  options: { code: number | string; label: string }[]
  value: AnswerValue
  onChange: (v: number | string) => void
}) {
  return (
    <div className="radio-group">
      {options.map((o) => (
        <label key={String(o.code)} className={value === o.code ? 'opt selected' : 'opt'}>
          <input
            type="radio"
            name={name}
            checked={value === o.code}
            onChange={() => onChange(o.code)}
          />
          <span>{o.label}</span>
        </label>
      ))}
    </div>
  )
}

export default function ItemInput({ item, value, onChange }: Props) {
  const rt = item.response_type

  // 0–4 ordinal coded scales + YES/NO/SKIP — radios with the scale's coded options.
  if (scales[rt] && scales[rt].options.length > 0) {
    return (
      <Radio
        name={item.variable}
        options={scales[rt].options.map((o) => ({ code: o.code, label: o.label }))}
        value={value}
        onChange={onChange}
      />
    )
  }

  // WB_LIFE_SAT — a 0–10 numeric scale.
  if (item.variable === 'WB_LIFE_SAT') {
    return (
      <div>
        <Radio
          name={item.variable}
          options={Array.from({ length: 11 }, (_, i) => ({ code: i, label: String(i) }))}
          value={value}
          onChange={onChange}
        />
        <button type="button" className="skip-link" onClick={() => onChange(99)}>
          Prefer not to answer
        </button>
      </div>
    )
  }

  // SINGLE — one choice from the option text.
  if (rt === 'SINGLE') {
    const opts = parseChoiceOptions(item)
    return (
      <Radio
        name={item.variable}
        options={opts.map((o) => ({ code: o, label: o }))}
        value={value}
        onChange={onChange}
      />
    )
  }

  // MULTI — any number of choices.
  if (rt === 'MULTI') {
    const opts = parseChoiceOptions(item)
    const selected = Array.isArray(value) ? value : []
    const toggle = (opt: string) =>
      onChange(selected.includes(opt) ? selected.filter((x) => x !== opt) : [...selected, opt])
    return (
      <div className="radio-group">
        {opts.map((o) => (
          <label key={o} className={selected.includes(o) ? 'opt selected' : 'opt'}>
            <input type="checkbox" checked={selected.includes(o)} onChange={() => toggle(o)} />
            <span>{o}</span>
          </label>
        ))}
      </div>
    )
  }

  // TEXT — unused in v0.1 (free text is disabled by the data-governance rule),
  // but render a disabled note in case the bank changes.
  return <p className="muted">Free-text responses are disabled in this instrument.</p>
}
