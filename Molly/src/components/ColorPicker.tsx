interface Props {
  value: string;
  onChange: (hex: string) => void;
  swatches?: string[];
  label?: string;
}

const DEFAULT_SWATCHES = [
  '#FFC0CB', '#FF8FB1', '#E5527A', '#D46BAA', '#9C4A85',
  '#C8102E', '#1A1A1A', '#FF4D4D', '#7D1431', '#3A0A18',
  '#D2B48C', '#A98863', '#8B6F47',
  '#FFB6C1', '#FF99CC', '#EC4899', '#F472B6', '#9D174D',
  '#00AFF0', '#0EA5E9', '#1E40AF',
  '#A16D9C', '#7C3AED',
];

function isHexLooking(v: string): boolean {
  return /^#[0-9a-fA-F]{6}$/.test(v.trim());
}

export function ColorPicker({ value, onChange, swatches = DEFAULT_SWATCHES, label }: Props) {
  return (
    <div className="flex flex-col gap-1">
      {label && <label className="text-xs uppercase tracking-wider opacity-60">{label}</label>}
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={isHexLooking(value) ? value : '#FFC0CB'}
          onChange={(e) => onChange(e.target.value)}
          className="w-10 h-9 rounded-lg border border-black/10 cursor-pointer p-0"
          title={value}
        />
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="pretty-input w-28 font-mono text-sm"
          spellCheck={false}
        />
        <div className="flex flex-wrap gap-1">
          {swatches.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => onChange(s)}
              title={s}
              style={{
                background: s,
                width: 18,
                height: 18,
                borderRadius: 6,
                border: s.toLowerCase() === value.toLowerCase() ? '2px solid black' : '1px solid rgba(0,0,0,0.15)',
              }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
