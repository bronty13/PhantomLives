import { useState } from 'react';
import type { CalendarBundle, FillerEntry, FillerSlot } from '../../model/types';
import { BIBLE_BOOKS, chapterCount, getRandomVerse, getVerse, verseCount, verseToFiller } from '../../data/bible';
import { rerollSaying } from '../../data/sayings';
import { Drawer } from '../components/Modal';

export function FillerPicker({ bundle, sayings, onChange, onClose }: { bundle: CalendarBundle; sayings: FillerEntry[]; onChange: (b: CalendarBundle) => void; onClose: () => void }) {
  const [slot, setSlot] = useState<FillerSlot>('footer');
  const [kind, setKind] = useState<'saying' | 'verse'>('verse');
  const [verseMode, setVerseMode] = useState<'random' | 'pick'>('random');

  const [saying, setSaying] = useState<FillerEntry>(() => rerollSaying(sayings, undefined));
  const [randVerse, setRandVerse] = useState<FillerEntry>(() => verseToFiller(getRandomVerse()));
  const [book, setBook] = useState('John');
  const [chapter, setChapter] = useState(3);
  const [verse, setVerse] = useState(16);

  const setFiller = (entry: FillerEntry) => {
    const fillers = bundle.fillers.filter((f) => f.slot !== slot);
    fillers.push({ slot, entry });
    onChange({ ...bundle, fillers });
  };
  const removeFiller = (s: FillerSlot) => onChange({ ...bundle, fillers: bundle.fillers.filter((f) => f.slot !== s) });

  const picked = getVerse(book, chapter, verse);

  const addCurrent = () => {
    if (kind === 'saying') setFiller(saying);
    else if (verseMode === 'random') setFiller(randVerse);
    else if (picked) setFiller(verseToFiller({ book, chapter, verse, text: picked.text, reference: picked.reference }));
  };

  return (
    <Drawer
      title="Sayings &amp; Verses"
      onClose={onClose}
      footer={<button className="primary" onClick={addCurrent}>Place in {slot === 'footer' ? 'footer' : 'grid free space'}</button>}
    >
      <p className="hint" style={{ marginTop: 0 }}>Fill the calendar’s free space with a saying or Bible verse.</p>

      {bundle.fillers.length > 0 && (
        <div className="col" style={{ marginBottom: 16 }}>
          <label style={{ margin: 0 }}>Current placements</label>
          {bundle.fillers.map((f) => (
            <div className="item-row" key={f.slot}>
              <span className="type-pill" style={{ background: 'var(--accent)' }}>{f.slot === 'footer' ? 'Footer' : 'Grid'}</span>
              <div className="grow">{f.entry.text}{f.entry.reference ? `  — ${f.entry.reference}` : ''}</div>
              <button className="ghost danger" onClick={() => removeFiller(f.slot)}>✕</button>
            </div>
          ))}
        </div>
      )}

      <div className="col">
        <div>
          <label>Where</label>
          <select value={slot} onChange={(e) => setSlot(e.target.value as FillerSlot)}>
            <option value="footer">Footer band (below the grid)</option>
            <option value="grid">Grid free space (empty day cells)</option>
          </select>
        </div>
        <div>
          <label>What</label>
          <div className="row" style={{ gap: 8 }}>
            <button className={kind === 'verse' ? 'primary' : ''} onClick={() => setKind('verse')}>Bible verse</button>
            <button className={kind === 'saying' ? 'primary' : ''} onClick={() => setKind('saying')}>Saying</button>
          </div>
        </div>

        {kind === 'saying' && (
          <div className="card" style={{ boxShadow: 'none' }}>
            <div style={{ fontStyle: 'italic' }}>{saying.text}</div>
            <div className="hint" style={{ marginTop: 6 }}>— {saying.reference}</div>
            <button style={{ marginTop: 10 }} onClick={() => setSaying(rerollSaying(sayings, saying.id))}>↻ Another saying</button>
          </div>
        )}

        {kind === 'verse' && (
          <>
            <div className="row" style={{ gap: 8 }}>
              <button className={verseMode === 'random' ? 'primary' : ''} onClick={() => setVerseMode('random')}>Random</button>
              <button className={verseMode === 'pick' ? 'primary' : ''} onClick={() => setVerseMode('pick')}>Pick a verse</button>
            </div>
            {verseMode === 'random' ? (
              <div className="card" style={{ boxShadow: 'none' }}>
                <div>{randVerse.text}</div>
                <div className="hint" style={{ marginTop: 6 }}>— {randVerse.reference}</div>
                <button style={{ marginTop: 10 }} onClick={() => setRandVerse(verseToFiller(getRandomVerse()))}>↻ Another verse</button>
              </div>
            ) : (
              <>
                <div className="row" style={{ gap: 8 }}>
                  <select value={book} onChange={(e) => { const b = e.target.value; setBook(b); setChapter(1); setVerse(1); }}>
                    {BIBLE_BOOKS.map((b) => <option key={b} value={b}>{b}</option>)}
                  </select>
                  <select value={chapter} onChange={(e) => { setChapter(parseInt(e.target.value, 10)); setVerse(1); }} style={{ width: 90 }}>
                    {Array.from({ length: chapterCount(book) }, (_, i) => i + 1).map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                  <select value={verse} onChange={(e) => setVerse(parseInt(e.target.value, 10))} style={{ width: 90 }}>
                    {Array.from({ length: verseCount(book, chapter) }, (_, i) => i + 1).map((v) => <option key={v} value={v}>{v}</option>)}
                  </select>
                </div>
                <div className="card" style={{ boxShadow: 'none' }}>
                  {picked ? <><div>{picked.text}</div><div className="hint" style={{ marginTop: 6 }}>— {picked.reference}</div></> : <span className="hint">No verse there.</span>}
                </div>
              </>
            )}
          </>
        )}
      </div>
    </Drawer>
  );
}
