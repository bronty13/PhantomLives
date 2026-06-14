import { useMemo, useState } from 'react';
import { BIBLE_BOOKS, chapterCount, verseCount, getVerse } from '../../data/bible';

interface Props {
  /** Fired when a complete, valid verse is chosen (verse tap, or Enter on a full reference). */
  onSelect: (text: string, reference: string) => void;
  /** Optional: book/chapter/verse to start drilled into (e.g. re-opening to edit). */
  initial?: { book?: string; chapter?: number; verse?: number };
}

const OT_COUNT = 39; // Genesis…Malachi; the rest (Matthew…Revelation) are NT.

/** Parse "john 3:16", "1 jo 5 4", "phil 4", or "psalm" into a book prefix + numbers. */
function parseQuery(q: string): { bookQuery: string; chapter: number | null; verse: number | null } {
  const t = q.trim();
  if (!t) return { bookQuery: '', chapter: null, verse: null };
  // Peel a trailing "chapter[:/space]verse" off the end; the rest is the book prefix.
  const m = t.match(/^(.+?)\s+(\d+)(?:\s*[:.\s]\s*(\d+))?$/);
  if (m) {
    return { bookQuery: m[1].trim(), chapter: parseInt(m[2], 10), verse: m[3] ? parseInt(m[3], 10) : null };
  }
  return { bookQuery: t, chapter: null, verse: null };
}

function matchBook(bookQuery: string): string | null {
  if (!bookQuery) return null;
  const lc = bookQuery.toLowerCase();
  return BIBLE_BOOKS.find((b) => b.toLowerCase().startsWith(lc)) ?? null;
}

/** Compact 3-char label so the book grid fits: "Genesis"→"Gen", "1 Samuel"→"1Sa". */
function abbrevBook(book: string): string {
  const m = book.match(/^(\d)\s+(.*)$/);
  if (m) return m[1] + m[2].slice(0, 2); // numbered books: digit + first 2 letters
  return book.slice(0, 3);
}

export function BibleVersePicker({ onSelect, initial }: Props) {
  const [query, setQuery] = useState('');
  const [book, setBook] = useState<string | null>(initial?.book ?? null);
  const [chapter, setChapter] = useState<number | null>(initial?.chapter ?? null);

  const parsed = useMemo(() => parseQuery(query), [query]);

  // While typing, books whose name starts with the typed prefix (case-insensitive).
  const filteredBooks = useMemo(() => {
    if (!parsed.bookQuery) return BIBLE_BOOKS;
    const lc = parsed.bookQuery.toLowerCase();
    return BIBLE_BOOKS.filter((b) => b.toLowerCase().startsWith(lc));
  }, [parsed.bookQuery]);

  // Typing live-overrides clicks so the grids follow you — but only once a chapter
  // number is present. A bare book prefix (e.g. "phil") just filters the book grid
  // so you can still choose among matches (Philippians vs Philemon).
  const typedBook = parsed.chapter != null && parsed.bookQuery ? matchBook(parsed.bookQuery) : null;
  const effBook = typedBook ?? book;
  const effChapter = parsed.chapter ?? chapter;

  const commit = (b: string, c: number, v: number) => {
    const verse = getVerse(b, c, v);
    if (verse) onSelect(verse.text, verse.reference);
  };

  const onEnter = () => {
    // Enter commits only when the typed reference resolves to a real verse.
    if (typedBook && parsed.chapter && parsed.verse && getVerse(typedBook, parsed.chapter, parsed.verse)) {
      commit(typedBook, parsed.chapter, parsed.verse);
    }
  };

  const previewVerse =
    effBook && effChapter && parsed.verse ? getVerse(effBook, effChapter, parsed.verse) : undefined;

  const gridBtn = (active: boolean): React.CSSProperties => ({
    padding: '4px 8px',
    minWidth: 30,
    textAlign: 'center',
    borderRadius: 4,
    border: `1px solid ${active ? 'var(--accent, #6b3f8a)' : 'var(--line, #d8d8d8)'}`,
    background: active ? 'var(--accent, #6b3f8a)' : 'transparent',
    color: active ? '#fff' : 'inherit',
    cursor: 'pointer',
    fontSize: 13,
  });

  const crumb = (label: string, onClick?: () => void, active = false) => (
    <button
      onClick={onClick}
      disabled={!onClick}
      style={{
        padding: '2px 8px',
        borderRadius: 4,
        border: 'none',
        background: active ? 'var(--accent, #6b3f8a)' : 'transparent',
        color: active ? '#fff' : onClick ? 'var(--accent, #6b3f8a)' : 'var(--muted, #888)',
        cursor: onClick ? 'pointer' : 'default',
        fontWeight: 600,
        fontSize: 13,
      }}
    >
      {label}
    </button>
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {/* Type-ahead jump box */}
      <input
        type="text"
        autoFocus
        value={query}
        placeholder="Type a reference — e.g. “John 3:16”, “1 Jo 5 4”, or “Psalm”"
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') onEnter(); }}
        style={{ padding: '7px 10px', borderRadius: 4, border: '1px solid var(--line, #d8d8d8)' }}
      />

      {/* Breadcrumb: Book › Chapter › Verse */}
      <div className="row" style={{ gap: 2, alignItems: 'center', flexWrap: 'wrap' }}>
        {crumb(
          effBook ?? 'Book',
          effBook ? () => { setQuery(''); setBook(null); setChapter(null); } : undefined,
          !effBook,
        )}
        {effBook && <span style={{ color: 'var(--muted, #aaa)' }}>›</span>}
        {effBook &&
          crumb(
            effChapter ? `Ch ${effChapter}` : 'Chapter',
            effChapter ? () => { setQuery(effBook); setBook(effBook); setChapter(null); } : undefined,
            !!effBook && !effChapter,
          )}
        {effBook && effChapter && <span style={{ color: 'var(--muted, #aaa)' }}>›</span>}
        {effBook && effChapter && crumb('Verse', undefined, true)}
      </div>

      {/* Step 1: pick a book (grid, grouped OT/NT) */}
      {!effBook && (
        <div style={{ maxHeight: 260, overflowY: 'auto' }}>
          {(['Old Testament', 'New Testament'] as const).map((section, si) => {
            const books = filteredBooks.filter((b) =>
              si === 0 ? BIBLE_BOOKS.indexOf(b) < OT_COUNT : BIBLE_BOOKS.indexOf(b) >= OT_COUNT,
            );
            if (books.length === 0) return null;
            return (
              <div key={section} style={{ marginBottom: 8 }}>
                <div style={{ fontSize: 11, textTransform: 'uppercase', color: 'var(--muted, #999)', margin: '4px 0' }}>{section}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                  {books.map((b) => (
                    <button
                      key={b}
                      style={{ ...gridBtn(false), minWidth: 38 }}
                      title={b}
                      aria-label={b}
                      onClick={() => { setQuery(''); setBook(b); setChapter(null); }}
                    >
                      {abbrevBook(b)}
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
          {filteredBooks.length === 0 && <div className="hint">No book matches “{parsed.bookQuery}”.</div>}
        </div>
      )}

      {/* Step 2: pick a chapter */}
      {effBook && !effChapter && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, maxHeight: 260, overflowY: 'auto' }}>
          {Array.from({ length: chapterCount(effBook) }, (_, i) => i + 1).map((c) => (
            <button key={c} style={gridBtn(false)} onClick={() => { setQuery(''); setBook(effBook); setChapter(c); }}>
              {c}
            </button>
          ))}
        </div>
      )}

      {/* Step 3: pick a verse (commits on click) */}
      {effBook && effChapter && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, maxHeight: 220, overflowY: 'auto' }}>
          {Array.from({ length: verseCount(effBook, effChapter) }, (_, i) => i + 1).map((v) => (
            <button key={v} style={gridBtn(parsed.verse === v)} onClick={() => commit(effBook, effChapter, v)}>
              {v}
            </button>
          ))}
        </div>
      )}

      {/* Live preview when a full reference is typed */}
      {previewVerse && (
        <div className="card" style={{ boxShadow: 'none', padding: 8 }}>
          <div style={{ fontSize: 13 }}>{previewVerse.text}</div>
          <div className="hint" style={{ marginTop: 4 }}>— {previewVerse.reference} · press Enter to use</div>
        </div>
      )}
    </div>
  );
}
