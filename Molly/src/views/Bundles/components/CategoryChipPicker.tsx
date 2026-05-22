import { useEffect, useMemo, useRef, useState } from 'react';
import { reorderBeforeTarget } from '../../../lib/reorderHelpers';

interface Props {
  /** Ordered list of UPPERCASE category names already on the bundle. */
  selected: string[];
  /** Pool of historical suggestions (also UPPERCASE) — typically the
   * union of every name ever used across bundles, freshest first. */
  suggestions: string[];
  onChange: (next: string[]) => void;
  disabled?: boolean;
}

/** Port of MasterClipper's CategoryChipPicker.swift to React. Chip grid
 * with drag-to-reorder + a dropdown for picking existing names + an
 * inline "create new" path that uppercases on save. */
export function CategoryChipPicker({ selected, suggestions, onChange, disabled }: Props) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const containerRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dropTargetId, setDropTargetId] = useState<string | null>(null);

  const selectedSet = useMemo(() => new Set(selected), [selected]);

  const matches = useMemo(() => {
    const q = query.trim().toUpperCase();
    const unselected = suggestions.filter((s) => !selectedSet.has(s));
    if (!q) return unselected;
    return unselected.filter((s) => s.includes(q));
  }, [suggestions, selectedSet, query]);

  const exactMatchExists = useMemo(() => {
    const q = query.trim().toUpperCase();
    if (!q) return true;
    return suggestions.some((s) => s === q) || selectedSet.has(q);
  }, [suggestions, selectedSet, query]);

  useEffect(() => {
    if (!open) return;
    const onDocClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDocClick);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDocClick);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 0);
    else setQuery('');
  }, [open]);

  function addName(raw: string) {
    const name = raw.trim().toUpperCase();
    if (!name) return;
    if (selectedSet.has(name)) return;
    onChange([...selected, name]);
  }
  function removeName(name: string) {
    onChange(selected.filter((s) => s !== name));
  }
  function onKeyDownSearch(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (matches.length > 0) { addName(matches[0]); setQuery(''); return; }
      if (query.trim() && !exactMatchExists) { addName(query); setQuery(''); }
    }
  }

  return (
    <div ref={containerRef} className="relative" id="bundle-categories" tabIndex={-1}>
      <div className="text-xs font-semibold opacity-75 mb-1">
        Categories <span className="opacity-60">(at least 3 — drag chips to reorder)</span>
      </div>
      <div className="flex flex-wrap gap-1.5 items-center">
        {selected.map((name, idx) => {
          const isDragging = draggingId === name;
          const isDropTarget = dropTargetId === name && draggingId !== null && draggingId !== name;
          return (
            <div
              key={name}
              draggable
              onDragStart={(e) => {
                setDraggingId(name);
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', name);
              }}
              onDragOver={(e) => {
                if (draggingId !== null && draggingId !== name) {
                  e.preventDefault();
                  e.dataTransfer.dropEffect = 'move';
                  if (dropTargetId !== name) setDropTargetId(name);
                }
              }}
              onDragLeave={() => { if (dropTargetId === name) setDropTargetId(null); }}
              onDrop={(e) => {
                e.preventDefault();
                if (draggingId !== null) onChange(reorderBeforeTarget(selected, (s) => s, draggingId, name));
                setDraggingId(null);
                setDropTargetId(null);
              }}
              onDragEnd={() => { setDraggingId(null); setDropTargetId(null); }}
              className="inline-flex items-center gap-1 pl-1.5 pr-1 py-1 rounded-full text-sm"
              style={{
                background: 'rgb(var(--persona-accent))',
                color: 'white',
                fontWeight: 600,
                cursor: isDragging ? 'grabbing' : 'grab',
                userSelect: 'none',
                opacity: isDragging ? 0.45 : 1,
                outline: isDropTarget ? '2px solid white' : 'none',
                outlineOffset: isDropTarget ? '1px' : 0,
              }}
              title="Drag to reorder"
            >
              <span aria-hidden className="opacity-70 text-[11px] leading-none px-0.5 font-mono">⋮⋮</span>
              <span className="opacity-80 text-[11px] font-mono">{idx + 1}.</span>
              <span className="font-mono tracking-wide">{name}</span>
              <button
                type="button"
                draggable={false}
                onMouseDown={(e) => e.stopPropagation()}
                onClick={(e) => { e.stopPropagation(); removeName(name); }}
                className="w-5 h-5 rounded-full bg-white/25 hover:bg-white/45 transition flex items-center justify-center text-xs leading-none"
                style={{ cursor: 'pointer' }}
                title={`Remove ${name}`}
                aria-label={`Remove ${name}`}
              >
                ×
              </button>
            </div>
          );
        })}
        <button
          type="button"
          disabled={disabled}
          onClick={() => setOpen((v) => !v)}
          className="px-2.5 py-1 rounded-full text-sm border border-dashed transition"
          style={{
            borderColor: 'rgb(var(--persona-primary) / 0.6)',
            color: 'rgb(var(--persona-text))',
            background: open ? 'rgb(var(--persona-tint))' : 'transparent',
          }}
        >
          + Add category
        </button>
      </div>

      {open && (
        <div
          className="absolute z-30 left-0 right-0 mt-2 rounded-2xl bg-white shadow-xl border border-black/10 overflow-hidden"
          style={{ maxWidth: '32rem' }}
        >
          <div className="p-2 border-b border-black/5">
            <input
              ref={inputRef}
              type="text"
              className="pretty-input w-full uppercase"
              placeholder="Search or type a new category and press Enter…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={onKeyDownSearch}
            />
          </div>
          <div className="max-h-72 overflow-y-auto">
            {query.trim() && !exactMatchExists && (
              <button
                type="button"
                onClick={() => { addName(query); setQuery(''); inputRef.current?.focus(); }}
                className="w-full text-left px-3 py-2 hover:bg-pink-50 transition border-b border-black/5 flex items-center gap-2"
              >
                <span className="text-pink-600">✨</span>
                <span className="font-medium">Create category: "{query.trim().toUpperCase()}"</span>
              </button>
            )}
            {matches.length === 0 && exactMatchExists && query.trim() && (
              <div className="px-3 py-3 text-sm opacity-60 italic">Already added.</div>
            )}
            {matches.length === 0 && !query.trim() && (
              <div className="px-3 py-3 text-sm opacity-60 italic">
                {suggestions.length === 0
                  ? 'No history yet — type above to create your first one.'
                  : 'All matches already selected.'}
              </div>
            )}
            {matches.map((name) => (
              <button
                key={name}
                type="button"
                onClick={() => { addName(name); setQuery(''); inputRef.current?.focus(); }}
                className="w-full text-left px-3 py-2 hover:bg-pink-50 transition border-b border-black/5 last:border-b-0 font-mono"
              >
                {name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
