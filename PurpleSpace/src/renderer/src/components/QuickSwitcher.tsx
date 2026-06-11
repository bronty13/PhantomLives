import React, { useEffect, useMemo, useRef, useState } from 'react';
import { breadcrumb, type PageMeta } from '../../../shared/tree';
import { DatabaseGlyph, PageGlyph } from '../lib/icons';

interface QuickSwitcherProps {
  pages: PageMeta[];
  onNavigate: (id: string) => void;
  onClose: () => void;
}

/** Cmd+P quick switcher: recents before you type, fuzzy title match after. */
export default function QuickSwitcher({ pages, onNavigate, onClose }: QuickSwitcherProps): React.JSX.Element {
  const [term, setTerm] = useState('');
  const [sel, setSel] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const results = useMemo(() => {
    if (!term.trim()) {
      return [...pages].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 9);
    }
    const needle = term.trim().toLowerCase();
    const scored = pages
      .map((p) => {
        const title = (p.title || 'Untitled').toLowerCase();
        let score = -1;
        if (title === needle) score = 100;
        else if (title.startsWith(needle)) score = 60;
        else if (title.includes(needle)) score = 30;
        else if (fuzzy(title, needle)) score = 10;
        return { p, score };
      })
      .filter((r) => r.score >= 0)
      .sort((a, b) => b.score - a.score || b.p.updatedAt - a.p.updatedAt);
    return scored.slice(0, 12).map((r) => r.p);
  }, [pages, term]);

  useEffect(() => setSel(0), [term]);
  useEffect(() => {
    inputRef.current?.focus();
  }, []);
  useEffect(() => {
    const items = listRef.current?.querySelectorAll('.qs-item');
    items?.[sel]?.scrollIntoView({ block: 'nearest' });
  }, [sel]);

  const pathFor = (id: string): string => {
    const chain = breadcrumb(pages, id);
    if (chain.length <= 1) return '';
    return chain
      .slice(0, -1)
      .map((c) => c.title || 'Untitled')
      .join(' / ');
  };

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="qs" onMouseDown={(e) => e.stopPropagation()}>
        <input
          ref={inputRef}
          className="qs-input"
          placeholder="Search pages…"
          value={term}
          onChange={(e) => setTerm(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Escape') onClose();
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              setSel((s) => Math.min(s + 1, results.length - 1));
            }
            if (e.key === 'ArrowUp') {
              e.preventDefault();
              setSel((s) => Math.max(s - 1, 0));
            }
            if (e.key === 'Enter' && results[sel]) onNavigate(results[sel]._id);
          }}
        />
        <div className="qs-list scrolly" ref={listRef}>
          {results.map((p, i) => (
            <button
              key={p._id}
              className={`qs-item ${i === sel ? 'sel' : ''}`}
              onMouseEnter={() => setSel(i)}
              onClick={() => onNavigate(p._id)}
            >
              <span className="tree-icon">
                {p.icon ?? (p.type === 'database' ? <DatabaseGlyph /> : <PageGlyph />)}
              </span>
              <span>{p.title || 'Untitled'}</span>
              <span className="qs-path">{pathFor(p._id)}</span>
            </button>
          ))}
          {results.length === 0 && <div className="qs-empty">No pages match “{term}”.</div>}
        </div>
      </div>
    </div>
  );
}

/** Subsequence fuzzy match. */
function fuzzy(haystack: string, needle: string): boolean {
  let i = 0;
  for (const ch of haystack) {
    if (ch === needle[i]) i++;
    if (i === needle.length) return true;
  }
  return false;
}
