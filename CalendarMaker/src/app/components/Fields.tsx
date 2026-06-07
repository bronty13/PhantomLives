import { useState } from 'react';
import { HexColorPicker } from 'react-colorful';
import { FONT_REGISTRY, cssFontFamily } from '../../data/fonts';
import type { FontKey } from '../../model/types';

export function ColorField({ value, onChange }: { value: string; onChange: (hex: string) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ position: 'relative' }}>
      <button className="row" style={{ gap: 8, padding: '6px 8px' }} onClick={() => setOpen((o) => !o)}>
        <span className="swatch" style={{ background: value }} />
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{value}</span>
      </button>
      {open && (
        <div style={{ position: 'absolute', zIndex: 20, marginTop: 6, background: '#fff', padding: 10, borderRadius: 10, boxShadow: 'var(--shadow)', border: '1px solid var(--line)' }}>
          <HexColorPicker color={value} onChange={onChange} />
          <input type="text" value={value} onChange={(e) => onChange(e.target.value)} style={{ marginTop: 8 }} />
          <button className="primary" style={{ marginTop: 8, width: '100%' }} onClick={() => setOpen(false)}>Done</button>
        </div>
      )}
    </div>
  );
}

export function FontPicker({ value, onChange }: { value: FontKey; onChange: (key: FontKey) => void }) {
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} style={{ fontFamily: cssFontFamily(value) }}>
      {FONT_REGISTRY.map((f) => (
        <option key={f.key} value={f.key} style={{ fontFamily: cssFontFamily(f.key) }}>
          {f.label}
        </option>
      ))}
    </select>
  );
}
