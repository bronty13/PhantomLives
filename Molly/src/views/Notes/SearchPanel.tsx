import { useEffect, useRef, useState } from 'react';
import {
  type FindHit, type NoteSummary,
  findInNotes, searchNoteTitles,
} from '../../data/notes';

interface Props {
  /** Fired when the user opens a search/find hit. For Search hits, only
   *  noteId is set (no line target). For Find hits, lineNo + snippet
   *  drive the editor's scroll-and-highlight. */
  onOpenHit: (target: { noteId: number; lineNo?: number; snippet?: string }) => void;
}

type Mode = 'search' | 'find';

export function SearchPanel({ onOpenHit }: Props) {
  const [mode, setMode] = useState<Mode>('search');
  const [query, setQuery] = useState('');
  const [regex, setRegex] = useState(false);
  const [titleHits, setTitleHits] = useState<NoteSummary[]>([]);
  const [bodyHits, setBodyHits] = useState<FindHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounce = useRef<number | null>(null);

  useEffect(() => {
    if (debounce.current != null) window.clearTimeout(debounce.current);
    if (!query.trim()) {
      setTitleHits([]); setBodyHits([]); setError(null);
      return;
    }
    debounce.current = window.setTimeout(async () => {
      setBusy(true); setError(null);
      try {
        if (mode === 'search') setTitleHits(await searchNoteTitles(query, regex));
        else setBodyHits(await findInNotes(query, regex));
      } catch (e) {
        setError(String((e as { message?: string })?.message ?? e));
      } finally { setBusy(false); }
    }, 250);
    return () => { if (debounce.current != null) window.clearTimeout(debounce.current); };
  }, [query, regex, mode]);

  return (
    <div className="rounded-2xl bg-white/55 border border-black/5 p-3 mb-3 space-y-2">
      <div className="flex items-center gap-1.5">
        <button
          type="button"
          onClick={() => setMode('search')}
          className="text-xs font-semibold px-2.5 py-1 rounded-full transition"
          style={{
            background: mode === 'search' ? 'rgb(var(--persona-accent))' : 'transparent',
            color: mode === 'search' ? 'white' : 'rgb(var(--persona-text) / 0.7)',
          }}
          title="Match titles"
        >
          🔍 Search
        </button>
        <button
          type="button"
          onClick={() => setMode('find')}
          className="text-xs font-semibold px-2.5 py-1 rounded-full transition"
          style={{
            background: mode === 'find' ? 'rgb(var(--persona-accent))' : 'transparent',
            color: mode === 'find' ? 'white' : 'rgb(var(--persona-text) / 0.7)',
          }}
          title="Match note bodies"
        >
          🔎 Find
        </button>
      </div>
      <div className="flex items-center gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={mode === 'search' ? 'Search titles…' : 'Find in note bodies…'}
          className="pretty-input flex-1 text-sm"
          spellCheck={false}
        />
        <label className="flex items-center gap-1 text-[11px] opacity-80 cursor-pointer">
          <input type="checkbox" checked={regex} onChange={(e) => setRegex(e.target.checked)} className="w-3.5 h-3.5" />
          .* regex
        </label>
      </div>
      {error && (
        <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-2.5 py-1.5">
          {error}
        </div>
      )}
      {busy && <div className="text-[11px] italic opacity-60">searching…</div>}
      {!busy && query.trim() !== '' && mode === 'search' && titleHits.length === 0 && !error && (
        <div className="text-[11px] italic opacity-60">no title matches</div>
      )}
      {!busy && query.trim() !== '' && mode === 'find' && bodyHits.length === 0 && !error && (
        <div className="text-[11px] italic opacity-60">no body matches</div>
      )}
      {mode === 'search' && titleHits.length > 0 && (
        <ul className="space-y-1 max-h-64 overflow-y-auto pr-1">
          {titleHits.map((n) => (
            <li key={n.id}>
              <button
                type="button"
                onClick={() => onOpenHit({ noteId: n.id })}
                className="w-full text-left px-2.5 py-1.5 rounded-xl hover:bg-black/5 text-xs"
              >
                <div className="font-semibold">{n.title}</div>
              </button>
            </li>
          ))}
        </ul>
      )}
      {mode === 'find' && bodyHits.length > 0 && (
        <ul className="space-y-1 max-h-64 overflow-y-auto pr-1">
          {bodyHits.map((h, i) => (
            <li key={`${h.noteId}-${h.lineNo}-${i}`}>
              <button
                type="button"
                onClick={() => onOpenHit({ noteId: h.noteId, lineNo: h.lineNo, snippet: h.snippet })}
                className="w-full text-left px-2.5 py-1.5 rounded-xl hover:bg-black/5 text-xs"
              >
                <div className="font-semibold">{h.noteTitle}</div>
                <div className="opacity-70 truncate"><span className="opacity-50">L{h.lineNo}:</span> {h.snippet}</div>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
