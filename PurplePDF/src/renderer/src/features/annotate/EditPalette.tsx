import type { Tool } from './types';

interface Props {
  tool: Tool;
  color: string;
  strokeWidth: number;
  onToolChange: (t: Tool) => void;
  onColorChange: (c: string) => void;
  onStrokeWidthChange: (w: number) => void;
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
  onToolChange,
  onColorChange,
  onStrokeWidthChange,
  onDeletePage,
  onRotatePage,
  onInsertBlank
}: Props): JSX.Element {
  return (
    <div className="edit-palette" role="toolbar" aria-label="Annotation tools">
      <div className="palette-group">
        {TOOLS.map((t) => (
          <button
            key={t.id}
            type="button"
            className={`palette-btn${tool === t.id ? ' active' : ''}`}
            onClick={() => onToolChange(t.id)}
            title={t.title}
            aria-pressed={tool === t.id}
          >
            <span aria-hidden="true">{t.icon}</span>
          </button>
        ))}
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
    </div>
  );
}
