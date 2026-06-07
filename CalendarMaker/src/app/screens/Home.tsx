import { useMemo, useRef, useState } from 'react';
import type { AppSettings, CalendarBundle, FillerEntry } from '../../model/types';
import { MONTH_NAMES } from '../../model/types';
import { randomVerseFiller } from '../../data/bible';
import { rerollSaying } from '../../data/sayings';
import { parseBundleFile } from '../../storage/bundleIO';
import { saveTheme } from '../../storage/db';
import { cssFontFamily } from '../../data/fonts';
import { greeting } from '../util';

interface Props {
  bundles: CalendarBundle[];
  settings: AppSettings;
  sayings: FillerEntry[];
  onOpen: (b: CalendarBundle) => void;
  onDelete: (id: string) => void;
  onNew: () => void;
  onImported: (b: CalendarBundle) => void;
  onImportTheme: () => void;
}

export function Home({ bundles, settings, sayings, onOpen, onDelete, onNew, onImported, onImportTheme }: Props) {
  const [verse, setVerse] = useState<FillerEntry>(() => randomVerseFiller());
  const [saying, setSaying] = useState<FillerEntry>(() => rerollSaying(sayings, undefined));
  const fileRef = useRef<HTMLInputElement>(null);
  const [err, setErr] = useState<string | null>(null);

  const importFile = async (file: File) => {
    try {
      const text = await file.text();
      const parsed = parseBundleFile(text);
      await saveTheme({ ...parsed.theme, builtin: false }); // ensure the bundle's theme exists locally
      onImportTheme();
      onImported(parsed.bundle);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Import failed.');
    }
  };

  return (
    <>
      <h1 style={{ fontFamily: "'CM Playfair', Georgia, serif", fontWeight: 700, fontSize: 28, margin: '4px 0 18px' }}>
        {greeting(settings.userName)}
      </h1>

      {(settings.showVerseOnHome || settings.showSayingOnHome) && (
        <div className="feature-cards">
          {settings.showVerseOnHome && (
            <FeatureCard
              kind="Verse of the moment"
              text={verse.text}
              reference={verse.reference}
              font="playfair"
              fg="#3a2a5a"
              bg="linear-gradient(135deg,#efe7fb,#f6f0ff)"
              onReroll={() => setVerse(randomVerseFiller(verse.reference))}
            />
          )}
          {settings.showSayingOnHome && (
            <FeatureCard
              kind="A little encouragement"
              text={saying.text}
              reference={saying.reference}
              font="caveat"
              fg="#2f6b5a"
              bg="linear-gradient(135deg,#e7f7ef,#f0fff6)"
              onReroll={() => setSaying(rerollSaying(sayings, saying.id))}
            />
          )}
        </div>
      )}

      <div className="row" style={{ marginBottom: 12 }}>
        <h2 className="section-title" style={{ margin: 0 }}>Your calendars</h2>
        <div style={{ flex: 1 }} />
        <button onClick={() => fileRef.current?.click()}>Import…</button>
        <button className="primary" onClick={onNew}>+ New calendar</button>
        <input
          ref={fileRef}
          type="file"
          accept=".json,application/json"
          style={{ display: 'none' }}
          onChange={(e) => { const f = e.target.files?.[0]; if (f) importFile(f); e.target.value = ''; }}
        />
      </div>

      {err && <div className="alert" style={{ marginBottom: 12 }}>{err}</div>}

      {bundles.length === 0 ? (
        <div className="empty">No calendars yet. Click <b>+ New calendar</b> to make your first one.</div>
      ) : (
        <div className="grid-cards">
          {bundles.map((b) => (
            <div className="card" key={b.id}>
              <h3>{b.title}</h3>
              <div className="meta">{MONTH_NAMES[b.month - 1]} {b.year}</div>
              <div className="meta">{Object.values(b.days).reduce((n, d) => n + d.items.length, 0)} item(s)</div>
              <div className="actions">
                <button className="primary" onClick={() => onOpen(b)}>Open</button>
                <button className="danger" onClick={() => { if (confirm(`Delete "${b.title}"? This cannot be undone.`)) onDelete(b.id); }}>Delete</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function FeatureCard({ kind, text, reference, font, fg, bg, onReroll }: { kind: string; text: string; reference?: string; font: string; fg: string; bg: string; onReroll: () => void }) {
  const family = useMemo(() => cssFontFamily(font), [font]);
  // The whole card is clickable (cursor + role) so a click anywhere rerolls —
  // not just a tiny corner glyph.
  return (
    <div
      className="feature clickable"
      style={{ background: bg, color: fg }}
      onClick={onReroll}
      role="button"
      tabIndex={0}
      title="Click for another"
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onReroll(); } }}
    >
      <span className="reroll" aria-hidden>↻ another</span>
      <div style={{ fontSize: 12, textTransform: 'uppercase', letterSpacing: 1, opacity: 0.7, marginBottom: 8 }}>{kind}</div>
      <div className="ftext" style={{ fontFamily: family }}>{text}</div>
      {reference && <div className="fref" style={{ fontFamily: family }}>— {reference}</div>}
    </div>
  );
}
