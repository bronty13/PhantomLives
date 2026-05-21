import { useEffect, useRef } from 'react';
import type { FindMatch } from './types';

interface Props {
  query: string;
  matches: FindMatch[];
  index: number;
  searching: boolean;
  onChange: (q: string) => void;
  onNext: () => void;
  onPrev: () => void;
  onClose: () => void;
}

export default function FindBar({
  query,
  matches,
  index,
  searching,
  onChange,
  onNext,
  onPrev,
  onClose
}: Props): JSX.Element {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  return (
    <div className="find-bar" role="search">
      <input
        ref={inputRef}
        type="search"
        placeholder="Find in document…"
        value={query}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            if (e.shiftKey) onPrev();
            else onNext();
          } else if (e.key === 'Escape') {
            e.preventDefault();
            onClose();
          }
        }}
        aria-label="Find in document"
      />
      <span className="find-count" aria-live="polite">
        {searching
          ? 'Searching…'
          : matches.length === 0
            ? query
              ? '0 matches'
              : ''
            : `${index + 1} / ${matches.length}`}
      </span>
      <button type="button" onClick={onPrev} disabled={matches.length === 0} aria-label="Previous match">
        ↑
      </button>
      <button type="button" onClick={onNext} disabled={matches.length === 0} aria-label="Next match">
        ↓
      </button>
      <button type="button" onClick={onClose} aria-label="Close find">
        ✕
      </button>
    </div>
  );
}
