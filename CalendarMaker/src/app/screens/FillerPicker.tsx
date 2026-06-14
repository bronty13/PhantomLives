import { useState } from 'react';
import type { CalendarBundle, FillerEntry, FillerSlot } from '../../model/types';
import { getRandomVerse, verseToFiller } from '../../data/bible';
import { rerollSaying } from '../../data/sayings';
import { Drawer } from '../components/Modal';
import { BibleVersePicker } from './BibleVersePicker';

export function FillerPicker({ bundle, sayings, onChange, onClose }: { bundle: CalendarBundle; sayings: FillerEntry[]; onChange: (b: CalendarBundle) => void; onClose: () => void }) {
  const [slot, setSlot] = useState<FillerSlot>('footer');
  const [kind, setKind] = useState<'saying' | 'verse'>('verse');
  const [verseMode, setVerseMode] = useState<'random' | 'pick'>('random');

  const [saying, setSaying] = useState<FillerEntry>(() => rerollSaying(sayings, undefined));
  const [randVerse, setRandVerse] = useState<FillerEntry>(() => verseToFiller(getRandomVerse()));
  // The verse chosen via the grid/type-ahead picker (pick mode).
  const [pickedVerse, setPickedVerse] = useState<FillerEntry | null>(null);

  const setFiller = (entry: FillerEntry) => {
    const fillers = bundle.fillers.filter((f) => f.slot !== slot);
    fillers.push({ slot, entry });
    onChange({ ...bundle, fillers });
  };
  const removeFiller = (s: FillerSlot) => onChange({ ...bundle, fillers: bundle.fillers.filter((f) => f.slot !== s) });

  const placeDisabled = kind === 'verse' && verseMode === 'pick' && !pickedVerse;

  const addCurrent = () => {
    if (kind === 'saying') setFiller(saying);
    else if (verseMode === 'random') setFiller(randVerse);
    else if (pickedVerse) setFiller(pickedVerse);
  };

  return (
    <Drawer
      title="Sayings &amp; Verses"
      onClose={onClose}
      footer={<button className="primary" onClick={addCurrent} disabled={placeDisabled}>Place in {slot === 'footer' ? 'footer' : 'grid free space'}</button>}
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
                <BibleVersePicker onSelect={(text, reference) => setPickedVerse({ id: `verse-${reference}`, kind: 'verse', text, reference })} />
                {pickedVerse && (
                  <div className="card" style={{ boxShadow: 'none' }}>
                    <div>{pickedVerse.text}</div>
                    <div className="hint" style={{ marginTop: 6 }}>— {pickedVerse.reference}</div>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>
    </Drawer>
  );
}
