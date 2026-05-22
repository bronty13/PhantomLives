import { useEffect, useRef, useState } from 'react';

/** The eleven fonts bundled in src/assets/fonts. Names match the
 *  @font-face declarations in src/styles/index.css. Paper Daisy is
 *  Sallie's default — listed first so the picker opens to it. */
export const NOTE_FONTS: { name: string; label: string }[] = [
  { name: 'Paper Daisy',           label: 'Paper Daisy' },
  { name: 'Caveat',                label: 'Caveat' },
  { name: 'Patrick Hand',          label: 'Patrick Hand' },
  { name: 'Indie Flower',          label: 'Indie Flower' },
  { name: 'Shadows Into Light',    label: 'Shadows Into Light' },
  { name: 'Architects Daughter',   label: 'Architects Daughter' },
  { name: 'Kalam',                 label: 'Kalam' },
  { name: 'Sacramento',            label: 'Sacramento' },
  { name: 'Amatic SC',             label: 'Amatic SC' },
  { name: 'Comfortaa',             label: 'Comfortaa' },
  { name: 'Quicksand',             label: 'Quicksand' },
];

/** Soft Apple-Notes / sticky-note palette. Names from the original
 *  Phase 13 plan. Custom hex is added inline by the picker as needed. */
export const PAPER_COLORS: { name: string; hex: string }[] = [
  { name: 'Paper white',  hex: '#fdfcf8' },
  { name: 'Buttercream',  hex: '#fff7d6' },
  { name: 'Blush',        hex: '#ffe4ec' },
  { name: 'Peach',        hex: '#ffe2cc' },
  { name: 'Mint',         hex: '#d6f5e3' },
  { name: 'Sky',          hex: '#dcefff' },
  { name: 'Lavender',     hex: '#ece4ff' },
  { name: 'Rose',         hex: '#fbd5dc' },
  { name: 'Dove',         hex: '#eeeeee' },
  { name: 'Sage',         hex: '#e2efd9' },
];

interface FontPickerProps {
  /** Selected font, or null = use default. */
  value: string | null;
  /** When provided, "Use default" rows the picker's reset option. */
  defaultName?: string;
  onChange: (next: string | null) => void;
  /** Compact mode for the inline editor button. */
  compact?: boolean;
}

export function FontPicker({ value, defaultName, onChange, compact = false }: FontPickerProps) {
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (!wrap.current?.contains(e.target as Node)) setOpen(false);
    }
    window.addEventListener('mousedown', onClick);
    return () => window.removeEventListener('mousedown', onClick);
  }, [open]);

  const labelText = value ?? defaultName ?? 'Paper Daisy';
  return (
    <div ref={wrap} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={compact ? 'pretty-button secondary text-xs' : 'pretty-button secondary text-sm'}
        title="Font"
        style={{ fontFamily: labelText }}
      >
        🖋 {labelText}{value == null && defaultName ? ' (default)' : ''}
      </button>
      {open && (
        <div className="absolute right-0 top-full mt-1 z-30 rounded-2xl bg-white shadow-lg border border-black/10 py-1 min-w-[220px] max-h-[60vh] overflow-y-auto">
          {defaultName && (
            <>
              <button
                type="button"
                onClick={() => { onChange(null); setOpen(false); }}
                className="w-full text-left text-xs px-3 py-1.5 hover:bg-black/5 italic opacity-70"
              >
                ↩ Use default ({defaultName})
              </button>
              <div className="border-t border-black/5" />
            </>
          )}
          {NOTE_FONTS.map((f) => (
            <button
              key={f.name}
              type="button"
              onClick={() => { onChange(f.name); setOpen(false); }}
              className="w-full text-left text-sm px-3 py-1.5 hover:bg-black/5 flex items-center gap-2"
              style={{ fontFamily: f.name }}
            >
              <span className="opacity-50 text-[10px] font-mono w-4">{f.name === value ? '✓' : ''}</span>
              <span className="flex-1">{f.label}</span>
              <span className="opacity-50 text-[10px]">Aa Aa</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

interface PaperColorPickerProps {
  /** Selected paper colour, or null = use default. */
  value: string | null;
  defaultHex?: string;
  onChange: (next: string | null) => void;
  compact?: boolean;
}

export function PaperColorPicker({ value, defaultHex, onChange, compact = false }: PaperColorPickerProps) {
  const [open, setOpen] = useState(false);
  const [customHex, setCustomHex] = useState(value && !PAPER_COLORS.some((p) => p.hex === value) ? value : '');
  const wrap = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (!wrap.current?.contains(e.target as Node)) setOpen(false);
    }
    window.addEventListener('mousedown', onClick);
    return () => window.removeEventListener('mousedown', onClick);
  }, [open]);

  const swatchHex = value ?? defaultHex ?? '#fdfcf8';
  return (
    <div ref={wrap} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={`${compact ? 'text-xs' : 'text-sm'} pretty-button secondary inline-flex items-center gap-2`}
        title="Paper colour"
      >
        🎨
        <span
          className="inline-block rounded-md border border-black/15"
          style={{ width: 16, height: 16, background: swatchHex }}
        />
        {value == null && defaultHex ? <span className="text-[10px] opacity-60">default</span> : null}
      </button>
      {open && (
        <div className="absolute right-0 top-full mt-1 z-30 rounded-2xl bg-white shadow-lg border border-black/10 p-3 min-w-[240px]">
          <div className="grid grid-cols-5 gap-2 mb-2">
            {PAPER_COLORS.map((p) => (
              <button
                key={p.hex}
                type="button"
                onClick={() => { onChange(p.hex); setOpen(false); }}
                title={p.name}
                style={{
                  background: p.hex,
                  width: 32, height: 32, borderRadius: 10,
                  border: p.hex === value
                    ? '2.5px solid rgb(var(--persona-accent))'
                    : '1px solid rgba(0,0,0,0.12)',
                }}
              />
            ))}
          </div>
          <div className="border-t border-black/5 my-2" />
          <label className="text-[10px] uppercase tracking-wider opacity-60">Custom</label>
          <div className="flex items-center gap-2 mt-1">
            <input
              type="color"
              value={customHex || swatchHex}
              onChange={(e) => setCustomHex(e.target.value)}
              className="w-8 h-8 rounded-md border border-black/10 cursor-pointer p-0"
            />
            <input
              type="text"
              value={customHex}
              onChange={(e) => setCustomHex(e.target.value)}
              placeholder="#aabbcc"
              className="pretty-input flex-1 font-mono text-xs"
              spellCheck={false}
            />
            <button
              type="button"
              onClick={() => {
                if (/^#[0-9a-f]{6}$/i.test(customHex.trim())) {
                  onChange(customHex.trim());
                  setOpen(false);
                }
              }}
              disabled={!/^#[0-9a-f]{6}$/i.test(customHex.trim())}
              className="pretty-button text-xs"
            >
              Apply
            </button>
          </div>
          {defaultHex && (
            <>
              <div className="border-t border-black/5 my-2" />
              <button
                type="button"
                onClick={() => { onChange(null); setOpen(false); }}
                className="w-full text-left text-xs px-2 py-1.5 italic opacity-70 hover:opacity-100"
              >
                ↩ Use default ({defaultHex})
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
