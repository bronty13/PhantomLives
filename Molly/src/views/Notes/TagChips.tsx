import { useRef, useState, useEffect } from 'react';
import type { NoteTag } from '../../data/notes';

interface Props {
  allTags: NoteTag[];
  selected: number[];           // tag ids currently on this note
  onChange: (next: number[]) => void;
  /** When true, missing tags get a + chip to add. */
  editable?: boolean;
  /** Compact mode for the notes-list row: smaller chips, no + button. */
  compact?: boolean;
}

export function TagChips({ allTags, selected, onChange, editable = true, compact = false }: Props) {
  const [pickerOpen, setPickerOpen] = useState(false);
  const pickerRef = useRef<HTMLDivElement | null>(null);

  // Close picker on outside click.
  useEffect(() => {
    if (!pickerOpen) return;
    function onClick(e: MouseEvent) {
      if (!pickerRef.current?.contains(e.target as Node)) setPickerOpen(false);
    }
    window.addEventListener('mousedown', onClick);
    return () => window.removeEventListener('mousedown', onClick);
  }, [pickerOpen]);

  const selectedSet = new Set(selected);
  const chosen = allTags.filter((t) => selectedSet.has(t.id));
  const available = allTags.filter((t) => !selectedSet.has(t.id));

  const sizeClass = compact ? 'text-[10px] px-1.5 py-0.5' : 'text-xs px-2.5 py-1';

  return (
    <div className="flex flex-wrap items-center gap-1.5 relative">
      {chosen.map((t) => (
        <span
          key={t.id}
          className={`${sizeClass} font-semibold rounded-full inline-flex items-center gap-1`}
          style={{ background: t.color, color: pickReadable(t.color) }}
        >
          #{t.name}
          {editable && (
            <button
              type="button"
              onClick={() => onChange(selected.filter((id) => id !== t.id))}
              className="opacity-50 hover:opacity-100"
              title="Remove tag"
            >
              ×
            </button>
          )}
        </span>
      ))}
      {editable && (
        <>
          <button
            type="button"
            onClick={() => setPickerOpen((v) => !v)}
            className={`${sizeClass} font-semibold rounded-full border border-dashed border-black/20 opacity-70 hover:opacity-100`}
            title="Add tag"
          >
            ＋ tag
          </button>
          {pickerOpen && (
            <div
              ref={pickerRef}
              className="absolute left-0 top-full mt-1 z-20 bg-white rounded-2xl shadow-lg border border-black/10 p-3 min-w-[220px]"
            >
              {available.length === 0 && chosen.length > 0 && (
                <div className="text-xs italic opacity-60 mb-2">All tags already on this note.</div>
              )}
              {available.length === 0 && chosen.length === 0 && (
                <div className="text-xs italic opacity-60 mb-2">No tags defined yet. Add some in Settings → 📝 Notes.</div>
              )}
              <div className="flex flex-wrap gap-1.5">
                {available.map((t) => (
                  <button
                    key={t.id}
                    type="button"
                    onClick={() => { onChange([...selected, t.id]); setPickerOpen(false); }}
                    className="text-xs px-2.5 py-1 font-semibold rounded-full hover:opacity-80 transition"
                    style={{ background: t.color, color: pickReadable(t.color) }}
                  >
                    #{t.name}
                  </button>
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function pickReadable(hex: string): string {
  const m = hex.match(/^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i);
  if (!m) return 'black';
  const r = parseInt(m[1], 16), g = parseInt(m[2], 16), b = parseInt(m[3], 16);
  const luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luma > 0.6 ? '#3a1431' : 'white';
}
