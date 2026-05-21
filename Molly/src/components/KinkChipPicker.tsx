import { useEffect, useMemo, useRef, useState } from 'react';

export interface KinkOption {
  id: number;
  name: string;
  description: string;
  color: string;
}

interface Props {
  options: KinkOption[];
  selected: number[];                            // selected ids in user order
  onChange: (ids: number[]) => void;
  onCreateKink: (name: string) => Promise<number | null>;
}

// Modeled on MasterClipper's CategoryChipPicker.swift — selected chips
// inline with ×, plus a + button that opens a searchable dropdown of
// unselected options with an inline-create row at the top when the
// search term doesn't match anything existing.
export function KinkChipPicker({ options, selected, onChange, onCreateKink }: Props) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  // Drag-to-reorder state: which id is being dragged, and which id is the
  // current hover target (so we can show a left-edge insertion indicator).
  const [draggingId, setDraggingId] = useState<number | null>(null);
  const [dropTargetId, setDropTargetId] = useState<number | null>(null);

  const byId = useMemo(() => new Map(options.map((o) => [o.id, o])), [options]);
  const selectedSet = useMemo(() => new Set(selected), [selected]);

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    const unselected = options.filter((o) => !selectedSet.has(o.id));
    if (!q) return unselected;
    return unselected.filter((o) => o.name.toLowerCase().includes(q));
  }, [options, selectedSet, query]);

  const exactMatchExists = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return options.some((o) => o.name.toLowerCase() === q);
  }, [options, query]);

  useEffect(() => {
    if (!open) return;
    const onDocClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDocClick);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDocClick);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  useEffect(() => {
    if (open) {
      setError(null);
      setTimeout(() => inputRef.current?.focus(), 0);
    } else {
      setQuery('');
    }
  }, [open]);

  function addId(id: number) {
    if (selectedSet.has(id)) return;
    onChange([...selected, id]);
  }

  function removeId(id: number) {
    onChange(selected.filter((x) => x !== id));
  }

  function reorderTo(srcId: number, targetId: number) {
    if (srcId === targetId) return;
    const srcIdx = selected.indexOf(srcId);
    const dstIdx = selected.indexOf(targetId);
    if (srcIdx < 0 || dstIdx < 0) return;
    const next = selected.slice();
    next.splice(srcIdx, 1);
    // Insert before the target (matching MasterClipper's drop-before-target
    // behavior). If the source was earlier in the list, the target index
    // shifts down by 1 after the splice.
    const insertAt = srcIdx < dstIdx ? dstIdx - 1 : dstIdx;
    next.splice(insertAt, 0, srcId);
    onChange(next);
  }

  async function createFromQuery() {
    const name = query.trim();
    if (!name || busy) return;
    setBusy(true);
    setError(null);
    try {
      const newId = await onCreateKink(name);
      if (newId != null) {
        onChange([...selected, newId]);
        setQuery('');
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  function onKeyDownSearch(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (matches.length > 0) {
        addId(matches[0].id);
        setQuery('');
        return;
      }
      if (query.trim() && !exactMatchExists) {
        void createFromQuery();
      }
    }
  }

  return (
    <div ref={containerRef} className="relative">
      <div className="flex flex-wrap gap-1.5 items-center">
        {selected.map((id, idx) => {
          const opt = byId.get(id);
          if (!opt) return null;
          const isDragging = draggingId === id;
          const isDropTarget = dropTargetId === id && draggingId !== null && draggingId !== id;
          return (
            <div
              key={id}
              draggable
              onDragStart={(e) => {
                setDraggingId(id);
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', String(id));
              }}
              onDragOver={(e) => {
                if (draggingId !== null && draggingId !== id) {
                  e.preventDefault();
                  e.dataTransfer.dropEffect = 'move';
                  if (dropTargetId !== id) setDropTargetId(id);
                }
              }}
              onDragLeave={() => {
                if (dropTargetId === id) setDropTargetId(null);
              }}
              onDrop={(e) => {
                e.preventDefault();
                if (draggingId !== null) reorderTo(draggingId, id);
                setDraggingId(null);
                setDropTargetId(null);
              }}
              onDragEnd={() => {
                setDraggingId(null);
                setDropTargetId(null);
              }}
              className="inline-flex items-center gap-1 pl-1.5 pr-1 py-1 rounded-full text-sm"
              style={{
                background: opt.color,
                color: 'white',
                fontWeight: 600,
                boxShadow: `0 3px 8px -4px ${opt.color}88`,
                cursor: isDragging ? 'grabbing' : 'grab',
                userSelect: 'none',
                WebkitUserSelect: 'none',
                opacity: isDragging ? 0.45 : 1,
                outline: isDropTarget ? '2px solid white' : 'none',
                outlineOffset: isDropTarget ? '1px' : 0,
              }}
              title={opt.description ? `${opt.description} — drag to reorder` : 'Drag to reorder'}
            >
              <span aria-hidden="true" className="opacity-70 text-[11px] leading-none px-0.5 font-mono">⋮⋮</span>
              <span className="opacity-80 text-[11px] font-mono">{idx + 1}.</span>
              <span>{opt.name}</span>
              <button
                type="button"
                draggable={false}
                onMouseDown={(e) => e.stopPropagation()}
                onClick={(e) => { e.stopPropagation(); removeId(id); }}
                className="w-5 h-5 rounded-full bg-white/25 hover:bg-white/45 transition flex items-center justify-center text-xs leading-none"
                style={{ cursor: 'pointer' }}
                title={`Remove ${opt.name}`}
                aria-label={`Remove ${opt.name}`}
              >
                ×
              </button>
            </div>
          );
        })}

        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="px-2.5 py-1 rounded-full text-sm border border-dashed transition"
          style={{
            borderColor: 'rgb(var(--persona-primary) / 0.6)',
            color: 'rgb(var(--persona-text))',
            background: open ? 'rgb(var(--persona-tint))' : 'transparent',
          }}
        >
          + Add kink
        </button>
      </div>

      {selected.length === 0 && !open && (
        <div className="text-xs opacity-60 italic mt-1.5">
          No kinks yet — click <strong>+ Add kink</strong> to search and add.
        </div>
      )}

      {open && (
        <div
          className="absolute z-30 left-0 right-0 mt-2 rounded-2xl bg-white shadow-xl border border-black/10 overflow-hidden"
          style={{ maxWidth: '32rem' }}
        >
          <div className="p-2 border-b border-black/5">
            <input
              ref={inputRef}
              type="text"
              className="pretty-input w-full"
              placeholder="Search kinks, or type a new name and press Enter…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={onKeyDownSearch}
            />
          </div>

          <div className="max-h-72 overflow-y-auto">
            {query.trim() && !exactMatchExists && (
              <button
                type="button"
                onClick={createFromQuery}
                disabled={busy}
                className="w-full text-left px-3 py-2 hover:bg-pink-50 transition border-b border-black/5 flex items-center gap-2"
              >
                <span className="text-pink-600">✨</span>
                <span className="font-medium">Create kink: "{query.trim()}"</span>
                {busy && <span className="text-xs opacity-60 ml-auto">creating…</span>}
              </button>
            )}

            {matches.length === 0 && exactMatchExists && query.trim() && (
              <div className="px-3 py-3 text-sm opacity-60 italic">
                Already added.
              </div>
            )}
            {matches.length === 0 && !query.trim() && (
              <div className="px-3 py-3 text-sm opacity-60 italic">
                All kinks selected — type above to create a new one.
              </div>
            )}

            {matches.map((o) => (
              <button
                key={o.id}
                type="button"
                onClick={() => { addId(o.id); setQuery(''); inputRef.current?.focus(); }}
                className="w-full text-left px-3 py-2 hover:bg-pink-50 transition border-b border-black/5 last:border-b-0"
              >
                <div className="font-medium text-sm">{o.name}</div>
                {o.description && (
                  <div className="text-xs opacity-70 line-clamp-2">{o.description}</div>
                )}
              </button>
            ))}
          </div>

          {error && (
            <div className="p-2 text-xs text-red-700 bg-red-50 border-t border-red-200">
              {error}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
