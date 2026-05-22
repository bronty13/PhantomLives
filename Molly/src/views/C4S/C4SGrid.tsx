import { useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listC4SClips, type C4SClip } from '../../data/c4sClips';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import { useC4SPrefs, type C4SColumnPrefs } from '../../state/c4sPrefs';

interface Props {
  active: Persona;
  onSelect: (clip: C4SClip) => void;
  /** Bumping this triggers a re-fetch (e.g. after a successful import). */
  refreshToken?: number;
}

type SortKey = 'clipId' | 'clipTitle' | 'clipStatus' | 'personaCode' | 'priceCents' | 'salesCount' | 'income6moCents';
type SortDir = 'asc' | 'desc';

interface ColumnDef {
  key: SortKey | 'categories' | 'keywords' | 'clipFilename' | 'clipThumbnail' | 'clipTrackingTag' | 'clipPreview';
  label: string;
  prefKey: keyof C4SColumnPrefs | null;       // null = always-shown
  sortable: boolean;
  defaultDir: SortDir;
  align?: 'left' | 'right';
}

const COLUMNS: readonly ColumnDef[] = [
  { key: 'personaCode',    label: 'Persona',   prefKey: null,             sortable: true,  defaultDir: 'asc' },
  { key: 'clipId',         label: 'Clip ID',   prefKey: 'clipId',         sortable: true,  defaultDir: 'desc' },
  { key: 'clipTitle',      label: 'Title',     prefKey: null,             sortable: true,  defaultDir: 'asc' },
  { key: 'clipStatus',     label: 'Status',    prefKey: 'clipStatus',     sortable: true,  defaultDir: 'asc' },
  { key: 'categories',     label: 'Categories',prefKey: 'categories',     sortable: false, defaultDir: 'asc' },
  { key: 'keywords',       label: 'Keywords',  prefKey: 'keywords',       sortable: false, defaultDir: 'asc' },
  { key: 'priceCents',     label: 'Price',     prefKey: 'price',          sortable: true,  defaultDir: 'desc', align: 'right' },
  { key: 'salesCount',     label: 'Sales',     prefKey: 'salesCount',     sortable: true,  defaultDir: 'desc', align: 'right' },
  { key: 'income6moCents', label: 'Income 6mo',prefKey: 'income6mo',      sortable: true,  defaultDir: 'desc', align: 'right' },
  { key: 'clipFilename',   label: 'Filename',  prefKey: 'clipFilename',   sortable: false, defaultDir: 'asc' },
  { key: 'clipThumbnail',  label: 'Thumbnail', prefKey: 'clipThumbnail',  sortable: false, defaultDir: 'asc' },
  { key: 'clipTrackingTag',label: 'Tracking',  prefKey: 'clipTrackingTag',sortable: false, defaultDir: 'asc' },
  { key: 'clipPreview',    label: 'Preview',   prefKey: 'clipPreview',    sortable: false, defaultDir: 'asc' },
];

function fmtMoneyCents(c: number | null | undefined): string {
  if (c == null) return '—';
  return `$${(c / 100).toFixed(2)}`;
}

const PERSONA_TINT: Record<string, { bg: string; fg: string }> = {
  CoC: { bg: '#FFC0CB', fg: '#5B2540' },
  PoA: { bg: '#C8102E', fg: '#FFFFFF' },
};

export function C4SGrid({ active, onSelect, refreshToken }: Props) {
  const [clips, setClips] = useState<C4SClip[]>([]);
  const [search, setSearch] = useState('');
  const [useRegex, setUseRegex] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('clipId');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [prefs] = useC4SPrefs();

  const personaScope = active.code === 'CoC' || active.code === 'PoA' ? active.code : undefined;

  const { loading } = useAsyncRefresh(async (alive) => {
    const rows = await listC4SClips({ personaCode: personaScope });
    if (!alive()) return;
    setClips(rows);
  }, [active.code, refreshToken]);

  const q = search.trim();
  let matcher: ((s: string) => boolean) | null = null;
  let regexError: string | null = null;
  if (q) {
    if (useRegex) {
      try {
        const re = new RegExp(q, 'i');
        matcher = (s) => re.test(s);
      } catch (e) {
        regexError = String(e).replace(/^SyntaxError:\s*/, '');
      }
    } else {
      const lower = q.toLowerCase();
      matcher = (s) => s.toLowerCase().includes(lower);
    }
  }

  const statusOptions = useMemo(() => {
    const s = new Set<string>();
    for (const c of clips) if (c.clipStatus) s.add(c.clipStatus);
    return [...s].sort((a, b) => a.localeCompare(b));
  }, [clips]);

  const filtered = useMemo(() => {
    return clips.filter((c) => {
      if (statusFilter && c.clipStatus !== statusFilter) return false;
      if (!matcher) return true;
      return (
        matcher(c.clipId) ||
        matcher(c.clipTitle) ||
        matcher(c.clipStatus) ||
        matcher(c.categories) ||
        matcher(c.keywords) ||
        matcher(c.clipFilename)
      );
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clips, statusFilter, q, useRegex]);

  const sorted = useMemo(() => {
    const copy = [...filtered];
    const mult = sortDir === 'asc' ? 1 : -1;
    copy.sort((a, b) => {
      switch (sortKey) {
        case 'clipId':         return mult * a.clipId.localeCompare(b.clipId, undefined, { numeric: true });
        case 'clipTitle':      return mult * a.clipTitle.localeCompare(b.clipTitle);
        case 'clipStatus':     return mult * a.clipStatus.localeCompare(b.clipStatus);
        case 'personaCode':    return mult * a.personaCode.localeCompare(b.personaCode);
        case 'priceCents':     return mult * ((a.priceCents ?? -1) - (b.priceCents ?? -1));
        case 'salesCount':     return mult * ((a.salesCount ?? -1) - (b.salesCount ?? -1));
        case 'income6moCents': return mult * ((a.income6moCents ?? -1) - (b.income6moCents ?? -1));
      }
    });
    return copy;
  }, [filtered, sortKey, sortDir]);

  const visibleCols = COLUMNS.filter((col) => {
    if (col.prefKey === null) return true;
    return prefs.columns[col.prefKey];
  });

  function clickSort(col: ColumnDef) {
    if (!col.sortable) return;
    if (sortKey === col.key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(col.key as SortKey);
      setSortDir(col.defaultDir);
    }
  }

  if (active.code === 'Sa') {
    return (
      <div className="pretty-card">
        <div className="text-sm opacity-70 italic">
          Sa (Sheer Attraction) doesn't have a Clips4Sale store — switch to CoC or PoA to see clips.
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap">
        <input
          className="pretty-input w-72"
          placeholder={useRegex ? 'Regex pattern (case-insensitive)…' : 'Search title, ID, category, keyword…'}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <label className="flex items-center gap-1 text-xs select-none whitespace-nowrap">
          <input
            type="checkbox"
            checked={useRegex}
            onChange={(e) => setUseRegex(e.target.checked)}
          />
          regex
        </label>
        {q && !regexError && (
          <div className="text-xs opacity-60 whitespace-nowrap">{sorted.length} of {clips.length}</div>
        )}
        <select
          className="pretty-input"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          disabled={statusOptions.length === 0}
        >
          <option value="">(any status)</option>
          {statusOptions.map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        {(q || statusFilter) && (
          <button type="button" className="pretty-button secondary" onClick={() => { setSearch(''); setStatusFilter(''); }}>
            Clear
          </button>
        )}
      </div>
      {regexError && (
        <div className="text-xs" style={{ color: '#B45309' }}>Invalid regex: {regexError}</div>
      )}

      <div className="pretty-card p-0 overflow-x-auto">
        {loading && <div className="text-sm opacity-60 italic p-4">Loading clips…</div>}
        {!loading && clips.length === 0 && (
          <div className="text-sm opacity-70 italic p-4">No C4S data for this persona yet — try the ✨ Import C4S CSV button on the dashboard.</div>
        )}
        {!loading && clips.length > 0 && sorted.length === 0 && (
          <div className="text-sm opacity-70 italic p-4">No clips match the current filter.</div>
        )}

        {!loading && sorted.length > 0 && (
          <table className="text-xs w-full">
            <thead>
              <tr className="text-left bg-black/[0.03]">
                {visibleCols.map((col) => (
                  <th
                    key={col.key}
                    onClick={() => clickSort(col)}
                    className={`px-3 py-2 font-semibold uppercase tracking-wider opacity-70 ${col.sortable ? 'cursor-pointer select-none' : ''} ${col.align === 'right' ? 'text-right' : ''}`}
                    title={col.sortable ? 'Click to sort; click again to flip' : undefined}
                  >
                    {col.label}
                    {col.sortable && sortKey === col.key && (sortDir === 'asc' ? ' ↑' : ' ↓')}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {sorted.map((c) => {
                const tint = PERSONA_TINT[c.personaCode];
                return (
                  <tr
                    key={`${c.personaCode}:${c.clipId}`}
                    onClick={() => onSelect(c)}
                    className="border-t border-black/5 cursor-pointer hover:bg-white/60"
                  >
                    {visibleCols.map((col) => {
                      const v = renderCell(col, c, tint);
                      return (
                        <td
                          key={col.key}
                          className={`px-3 py-2 ${col.align === 'right' ? 'text-right font-mono' : ''}`}
                          style={col.key === 'clipTitle' ? { maxWidth: 360 } : undefined}
                        >
                          {v}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function renderCell(col: ColumnDef, c: C4SClip, tint: { bg: string; fg: string } | undefined): React.ReactNode {
  switch (col.key) {
    case 'personaCode':
      return (
        <span
          className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold inline-block"
          style={{ background: tint?.bg ?? '#ddd', color: tint?.fg ?? '#222' }}
        >
          {c.personaCode}
        </span>
      );
    case 'clipId':
      return <span className="font-mono opacity-80">{c.clipId}</span>;
    case 'clipTitle':
      return <span className="font-semibold truncate block" title={c.clipTitle}>{c.clipTitle || '(untitled)'}</span>;
    case 'clipStatus':
      return c.clipStatus;
    case 'categories':
      return <span className="opacity-80">{c.categories || '—'}</span>;
    case 'keywords':
      return <span className="opacity-80">{c.keywords || '—'}</span>;
    case 'priceCents':
      return fmtMoneyCents(c.priceCents);
    case 'salesCount':
      return c.salesCount == null ? '—' : c.salesCount.toLocaleString();
    case 'income6moCents':
      return fmtMoneyCents(c.income6moCents);
    case 'clipFilename':
      return <span className="font-mono opacity-70">{c.clipFilename || '—'}</span>;
    case 'clipThumbnail':
      return <span className="font-mono opacity-70">{c.clipThumbnail || '—'}</span>;
    case 'clipTrackingTag':
      return c.clipTrackingTag || '—';
    case 'clipPreview':
      return <span className="font-mono opacity-70">{c.clipPreview || '—'}</span>;
  }
}
