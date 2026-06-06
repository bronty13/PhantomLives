import { useState } from 'react';
import { HexColorPicker } from 'react-colorful';

/** A labelled swatch that opens a popover color picker plus a hex text input. */
export function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (hex: string) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="color-field">
      <span className="field-label">{label}</span>
      <div className="color-row">
        <button
          type="button"
          className="swatch"
          style={{ background: value }}
          onClick={() => setOpen((o) => !o)}
          aria-label={`Pick ${label}`}
        />
        <input
          className="hex-input"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          spellCheck={false}
        />
      </div>
      {open && (
        <div className="color-pop">
          <HexColorPicker color={value} onChange={onChange} />
          <button type="button" className="btn small secondary" onClick={() => setOpen(false)}>Done</button>
        </div>
      )}
    </div>
  );
}
