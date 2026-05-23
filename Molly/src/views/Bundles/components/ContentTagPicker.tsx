import type { ContentTag } from '../../../data/contentTags';

interface Props {
  tags: ContentTag[];
  selected: number[];
  onChange: (next: number[]) => void;
  disabled?: boolean;
}

/** Cute multi-select chip group for content tags.
 *  Tags are global (Settings → Holidays… no, Settings → Content tags),
 *  so this picker is a flat row reused by every bundle form. */
export function ContentTagPicker({ tags, selected, onChange, disabled }: Props) {
  const selectedSet = new Set(selected);

  function toggle(tagId: number) {
    if (disabled) return;
    if (selectedSet.has(tagId)) {
      onChange(selected.filter((t) => t !== tagId));
    } else {
      onChange([...selected, tagId]);
    }
  }

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <label className="text-xs font-semibold opacity-75">
          Content tags <span className="opacity-50">(0 or many — used for search + reporting)</span>
        </label>
        {selected.length > 0 && (
          <button
            type="button"
            className="text-xs opacity-60 hover:opacity-100"
            onClick={() => onChange([])}
            disabled={disabled}
          >
            clear
          </button>
        )}
      </div>
      {tags.length === 0 ? (
        <div className="text-xs italic opacity-60">
          No content tags defined yet — add some in <strong>Settings → Content tags</strong>.
        </div>
      ) : (
        <div className="flex flex-wrap gap-1.5">
          {tags.map((t) => {
            const on = selectedSet.has(t.id);
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => toggle(t.id)}
                disabled={disabled}
                className="px-2.5 py-1 rounded-full text-xs font-semibold transition"
                style={chipStyle(t.color, on)}
                title={on ? `Remove ${t.name}` : `Add ${t.name}`}
              >
                {on && <span className="mr-1" aria-hidden>✓</span>}
                {t.name}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function ReadonlyTagPill({ tag }: { tag: ContentTag }) {
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold whitespace-nowrap"
      style={chipStyle(tag.color, true)}
    >
      {tag.name}
    </span>
  );
}

function chipStyle(color: string, on: boolean): React.CSSProperties {
  if (on) {
    return {
      background: color,
      color: idealTextColor(color),
      border: `1px solid ${darken(color, 0.15)}`,
      boxShadow: `0 1px 3px ${color}66`,
    };
  }
  return {
    background: `${color}26`,             // soft tint
    color: darken(color, 0.4),
    border: `1px solid ${color}80`,
  };
}

/** Black for light backgrounds, white for dark — quick luminance test
 *  using the same coefficients as WCAG relative-luminance. */
function idealTextColor(hex: string): string {
  const { r, g, b } = parseHex(hex);
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 160 ? '#1F2937' : '#FFFFFF';
}

function darken(hex: string, amount: number): string {
  const { r, g, b } = parseHex(hex);
  const k = 1 - Math.max(0, Math.min(1, amount));
  return rgbHex(Math.round(r * k), Math.round(g * k), Math.round(b * k));
}

function parseHex(hex: string): { r: number; g: number; b: number } {
  const h = hex.replace('#', '');
  if (h.length !== 6) return { r: 200, g: 200, b: 200 };
  return {
    r: parseInt(h.slice(0, 2), 16),
    g: parseInt(h.slice(2, 4), 16),
    b: parseInt(h.slice(4, 6), 16),
  };
}

function rgbHex(r: number, g: number, b: number): string {
  return `#${[r, g, b].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')).join('')}`;
}
