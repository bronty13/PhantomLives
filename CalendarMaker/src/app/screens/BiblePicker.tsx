import { useState, useMemo } from 'react';
import { BIBLE_BOOKS, chapterCount, verseCount, getVerse } from '../../data/bible';

interface BiblePickerProps {
  onSelect: (text: string, reference: string) => void;
  onClose?: () => void;
}

export function BiblePicker({ onSelect, onClose }: BiblePickerProps) {
  const [selectedBook, setSelectedBook] = useState<string>(BIBLE_BOOKS[0]);
  const [selectedChapter, setSelectedChapter] = useState<number>(1);
  const [selectedVerse, setSelectedVerse] = useState<number>(1);

  const chapters = useMemo(() => {
    const count = chapterCount(selectedBook);
    return Array.from({ length: count }, (_, i) => i + 1);
  }, [selectedBook]);

  const verses = useMemo(() => {
    const count = verseCount(selectedBook, selectedChapter);
    return Array.from({ length: count }, (_, i) => i + 1);
  }, [selectedBook, selectedChapter]);

  const handleSelect = () => {
    const verse = getVerse(selectedBook, selectedChapter, selectedVerse);
    if (verse) {
      onSelect(verse.text, verse.reference);
      onClose?.();
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <label>Book</label>
        <select value={selectedBook} onChange={(e) => {
          setSelectedBook(e.target.value);
          setSelectedChapter(1);
          setSelectedVerse(1);
        }}>
          {BIBLE_BOOKS.map((book) => (
            <option key={book} value={book}>{book}</option>
          ))}
        </select>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <label>Chapter</label>
        <select value={selectedChapter} onChange={(e) => {
          const ch = parseInt(e.target.value, 10);
          setSelectedChapter(ch);
          setSelectedVerse(1);
        }}>
          {chapters.map((ch) => (
            <option key={ch} value={ch}>{ch}</option>
          ))}
        </select>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <label>Verse</label>
        <select value={selectedVerse} onChange={(e) => setSelectedVerse(parseInt(e.target.value, 10))}>
          {verses.map((v) => (
            <option key={v} value={v}>{v}</option>
          ))}
        </select>
      </div>

      <button className="primary" onClick={handleSelect} style={{ marginTop: 8 }}>
        Select Verse
      </button>
    </div>
  );
}
