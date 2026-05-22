import { useEffect, useRef, useState } from 'react';
import type { Tool } from './types';
import { STAMP_PRESETS } from './stamps';
import type { ArmedStamp } from './AnnotationLayer';

interface Props {
  tool: Tool;
  color: string;
  strokeWidth: number;
  armedStamp: ArmedStamp | null;
  onToolChange: (t: Tool) => void;
  onColorChange: (c: string) => void;
  onStrokeWidthChange: (w: number) => void;
  /** Arm (or disarm) a stamp preset. Passing null disarms. Auto-switches tool to 'stamp'. */
  onArmStamp: (s: ArmedStamp | null) => void;
  onDeletePage: () => void;
  onRotatePage: () => void;
  onInsertBlank: () => void;
}

const TOOLS: { id: Tool; label: string; icon: string; title: string }[] = [
  { id: 'select', label: 'Select', icon: '↖', title: 'Select / move (V)' },
  { id: 'highlight', label: 'Highlight', icon: '▮', title: 'Highlight text' },
  { id: 'underline', label: 'Underline', icon: 'U', title: 'Underline text' },
  { id: 'strikethrough', label: 'Strike', icon: 'S̶', title: 'Strikethrough text' },
  { id: 'note', label: 'Note', icon: '✎', title: 'Sticky note' },
  { id: 'freehand', label: 'Draw', icon: '✐', title: 'Freehand draw' },
  { id: 'rect', label: 'Box', icon: '▢', title: 'Rectangle' },
  { id: 'textbox', label: 'Text', icon: 'T', title: 'Text box' },
  { id: 'signature', label: 'Sign', icon: '✍', title: 'Place signature' },
  { id: 'redact', label: 'Redact', icon: '■', title: 'Visual redaction (blackout)' },
  { id: 'stamp', label: 'Stamp', icon: '✪', title: 'Place a business stamp (Approved, Denied, …)' },
  { id: 'crop', label: 'Crop', icon: '⌗', title: 'Crop current page (drag a rectangle)' }
];

const COLOR_SWATCHES = [
  '#FACC15', // yellow
  '#F87171', // red
  '#34D399', // green
  '#60A5FA', // blue
  '#A78BFA', // purple
  '#F472B6', // pink
  '#FFFFFF', // white
  '#111827'  // near black
];

const SIZE_PRESETS: { id: string; label: string; width: number; dot: number }[] = [
  { id: 'xs', label: 'Extra small', width: 1, dot: 4 },
  { id: 's', label: 'Small', width: 2, dot: 7 },
  { id: 'm', label: 'Medium', width: 4, dot: 11 },
  { id: 'l', label: 'Large', width: 8, dot: 15 },
  { id: 'xl', label: 'Extra large', width: 16, dot: 20 }
];

export default function EditPalette({
  tool,
  color,
  strokeWidth,
  armedStamp,
  onToolChange,
  onColorChange,
  onStrokeWidthChange,
  onArmStamp,
  onDeletePage,
  onRotatePage,
  onInsertBlank
}: Props): JSX.Element {
  const [stampPickerOpen, setStampPickerOpen] = useState(false);
  const [includeDate, setIncludeDate] = useState(true);
  const [includeUser, setIncludeUser] = useState(true);
  const stampBtnRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);

  // Close stamp picker when clicking outside it.
  useEffect(() => {
    if (!stampPickerOpen) return;
    const onDown = (e: MouseEvent): void => {
      const t = e.target as Node;
      if (popoverRef.current?.contains(t)) return;
      if (stampBtnRef.current?.contains(t)) return;
      setStampPickerOpen(false);
    };
    window.addEventListener('mousedown', onDown);
    return () => window.removeEventListener('mousedown', onDown);
  }, [stampPickerOpen]);

  const handleToolClick = (t: Tool): void => {
    if (t === 'stamp') {
      // Toggle the picker; selecting a preset both arms it and switches tool.
      setStampPickerOpen((v) => !v);
      return;
    }
    setStampPickerOpen(false);
    onToolChange(t);
  };

  return (
    <div className="edit-palette" role="toolbar" aria-label="Annotation tools">
      <div className="palette-group">
        {TOOLS.map((t) => {
          const active =
            tool === t.id ||
            (t.id === 'stamp' && tool === 'stamp' && !!armedStamp);
          return (
            <button
              key={t.id}
              ref={t.id === 'stamp' ? stampBtnRef : undefined}
              type="button"
              className={`palette-btn${active ? ' active' : ''}`}
              onClick={() => handleToolClick(t.id)}
              title={t.title}
              aria-pressed={active}
              aria-haspopup={t.id === 'stamp' ? 'menu' : undefined}
              aria-expanded={t.id === 'stamp' ? stampPickerOpen : undefined}
            >
              <span aria-hidden="true">{t.icon}</span>
            </button>
          );
        })}
      </div>
      <div className="palette-group">
        {COLOR_SWATCHES.map((c) => (
          <button
            key={c}
            type="button"
            className={`swatch${color.toUpperCase() === c.toUpperCase() ? ' active' : ''}`}
            style={{ background: c }}
            onClick={() => onColorChange(c)}
            aria-label={`Color ${c}`}
          />
        ))}
      </div>
      <div className="palette-group palette-size" role="radiogroup" aria-label="Stroke size">
        <span className="palette-label">Size:</span>
        {SIZE_PRESETS.map((s) => {
          const active = Math.abs(strokeWidth - s.width) < 0.5;
          return (
            <button
              key={s.id}
              type="button"
              role="radio"
              aria-checked={active}
              className={`size-btn${active ? ' active' : ''}`}
              onClick={() => onStrokeWidthChange(s.width)}
              title={`${s.label} (${s.width} pt)`}
            >
              <span
                className="size-dot"
                style={{
                  width: s.dot,
                  height: s.dot,
                  background: color
                }}
              />
            </button>
          );
        })}
      </div>
      <div className="palette-group palette-page-ops">
        <span className="palette-label">Page:</span>
        <button type="button" onClick={onRotatePage} title="Rotate current page 90° CW">
          ↻
        </button>
        <button type="button" onClick={onInsertBlank} title="Insert blank page after current">
          +blank
        </button>
        <button type="button" onClick={onDeletePage} title="Delete current page" className="danger">
          ⌫
        </button>
      </div>

      {stampPickerOpen && (
        <div ref={popoverRef} className="stamp-picker" role="menu" aria-label="Stamp presets">
          <div className="stamp-picker-header">
            <span>Choose a stamp</span>
            <div className="stamp-toggles">
              <label className="stamp-date-toggle">
                <input
                  type="checkbox"
                  checked={includeUser}
                  onChange={(e) => setIncludeUser(e.target.checked)}
                />
                <span>Include user</span>
              </label>
              <label className="stamp-date-toggle">
                <input
                  type="checkbox"
                  checked={includeDate}
                  onChange={(e) => setIncludeDate(e.target.checked)}
                />
                <span>Include date/time</span>
              </label>
            </div>
          </div>
          <div className="stamp-picker-grid">
            {STAMP_PRESETS.map((p) => (
              <button
                key={p.id}
                type="button"
                role="menuitem"
                className="stamp-preset"
                style={{ borderColor: p.color, color: p.color }}
                title={p.style === 'mark' ? `Mark: ${p.label}` : p.label}
                onClick={() => {
                  onArmStamp({
                    label: p.label,
                    style: p.style,
                    color: p.color,
                    width: p.width,
                    height: p.height,
                    includeDate: p.style === 'mark' ? false : includeDate,
                    includeUser: p.style === 'mark' ? false : includeUser
                  });
                  // Switching to the stamp tool happens via onArmStamp in the parent.
                  setStampPickerOpen(false);
                }}
              >
                <span className="stamp-preset-label">{p.label}</span>
              </button>
            ))}
          </div>
          {armedStamp && (
            <div className="stamp-picker-footer">
              <span>
                Armed: <strong>{armedStamp.label}</strong>
                {armedStamp.includeUser || armedStamp.includeDate
                  ? ` (${[armedStamp.includeUser && 'user', armedStamp.includeDate && 'date']
                      .filter(Boolean)
                      .join(' + ')})`
                  : ''}
              </span>
              <button type="button" className="link-btn" onClick={() => onArmStamp(null)}>
                Disarm
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
