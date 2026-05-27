import { useEffect, useMemo, useState } from 'react';
import { readDocText, revealWorkingFile, type BundleManifest } from '../../data/bundles';
import { parseMarkdownLite } from '../../lib/markdownLite';
import { MarkdownBlocks } from '../../components/Markdown';

export type DocKind = 'manifest' | 'log' | 'info';

interface Props {
  uid: string;
  kind: DocKind | null;
  manifest: BundleManifest | null;
  onClose: () => void;
}

const FILE_FOR_KIND: Record<DocKind, string> = {
  manifest: 'manifest.json',
  log: 'Molly.log',
  info: 'info.md',
};

const TITLE_FOR_KIND: Record<DocKind, string> = {
  manifest: 'Manifest',
  log: 'Molly.log',
  info: 'info.md',
};

export function DocDrawer({ uid, kind, manifest, onClose }: Props) {
  const [text, setText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!kind) { setText(null); setError(null); return; }
    if (kind === 'manifest') { setText(null); setError(null); return; }
    let alive = true;
    (async () => {
      try {
        const t = await readDocText(uid, FILE_FOR_KIND[kind]);
        if (alive) { setText(t); setError(null); }
      } catch (e) {
        if (alive) { setText(null); setError(String(e)); }
      }
    })();
    return () => { alive = false; };
  }, [uid, kind]);

  // Hoisted memo: parsing the markdown body needs to be a hook called
  // on EVERY render, never conditionally. Calling useMemo inside the
  // JSX ternary was a Rules-of-Hooks violation — first render with
  // kind=null used 3 hooks, then kind=info used 4 and React panic'd
  // → blank screen requiring app restart. Fixed by always calling
  // useMemo, but no-op'ing when the body isn't needed.
  const infoBlocks = useMemo(() => {
    if (kind !== 'info' || text == null) return [];
    return parseMarkdownLite(text);
  }, [kind, text]);

  if (!kind) return null;

  const reveal = () => {
    revealWorkingFile(uid, FILE_FOR_KIND[kind]).catch(() => {});
  };

  return (
    <>
      <div
        onClick={onClose}
        className="fixed inset-0 z-40"
        style={{ background: 'rgba(0,0,0,0.25)' }}
      />
      <aside
        className="fixed top-0 right-0 bottom-0 z-50 flex flex-col"
        style={{
          width: 'min(620px, 80vw)',
          background: 'rgb(var(--surface-card))',
          borderLeft: '1px solid rgb(var(--surface-border))',
          boxShadow: '-12px 0 24px -8px rgba(0,0,0,0.12)',
        }}
      >
        <header className="flex items-center gap-3 px-5 py-3 shrink-0"
                style={{ borderBottom: '1px solid rgb(var(--surface-border))' }}>
          <div className="display-font text-xl flex-1" style={{ color: 'rgb(var(--surface-accent))' }}>
            {TITLE_FOR_KIND[kind]}
          </div>
          <button type="button" className="sm-button secondary text-xs" onClick={reveal}>
            📁 Reveal
          </button>
          <button type="button" className="sm-button secondary text-xs" onClick={onClose}>
            ✕ Close
          </button>
        </header>
        <div className="flex-1 overflow-y-auto px-5 py-4">
          {kind === 'manifest' && manifest && <ManifestPretty m={manifest} />}
          {kind === 'log' && (
            error ? <ErrorBox msg={error} /> :
            text == null ? <Loading /> :
            <pre className="font-mono text-xs whitespace-pre-wrap"
                 style={{ color: 'rgb(var(--surface-text))' }}>{text}</pre>
          )}
          {kind === 'info' && (
            error ? <ErrorBox msg={error} /> :
            text == null ? <Loading /> :
            <MarkdownBlocks blocks={infoBlocks} />
          )}
        </div>
      </aside>
    </>
  );
}

function Loading() {
  return <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
}

function ErrorBox({ msg }: { msg: string }) {
  return (
    <div className="text-sm sm-card" style={{ color: '#c4252e', background: '#ffe4e4' }}>
      {msg}
    </div>
  );
}

function ManifestPretty({ m }: { m: BundleManifest }) {
  const Row = ({ k, v }: { k: string; v: React.ReactNode }) => (
    <div className="grid grid-cols-[140px_1fr] gap-x-4 py-1 text-sm">
      <div className="text-xs uppercase tracking-wider pt-1" style={{ color: 'rgb(var(--surface-muted))' }}>{k}</div>
      <div>{v}</div>
    </div>
  );
  return (
    <div className="flex flex-col">
      <Row k="UID"           v={<code className="text-xs">{m.uid}</code>} />
      <Row k="Type"          v={m.bundleType} />
      <Row k="Persona"       v={m.personaCode ?? '(unassigned)'} />
      <Row k="Title"         v={m.title} />
      {m.contentDate && <Row k="Content date" v={m.contentDate} />}
      {m.goLiveDate && <Row k="Go-live date"  v={m.goLiveDate} />}
      {m.publishedAt && <Row k="Published"    v={<code className="text-xs">{m.publishedAt}</code>} />}
      {m.bundleType === 'content' && (
        <>
          {m.descriptionMode && <Row k="Description mode" v={m.descriptionMode} />}
          {m.descriptionText && <Row k="Description"
            v={<pre className="text-xs whitespace-pre-wrap">{m.descriptionText}</pre>} />}
          {m.descriptionAudioPath && <Row k="Audio" v={<code>{m.descriptionAudioPath}</code>} />}
          {m.categories.length > 0 && <Row k="Categories" v={
            <div className="flex flex-wrap gap-1.5">
              {m.categories.map((c, i) => (
                <span key={i} className="text-xs px-1.5 py-0.5 rounded"
                      style={{ background: 'rgb(var(--surface-accent) / 0.12)', color: 'rgb(var(--surface-accent))' }}>
                  {c}
                </span>
              ))}
            </div>
          } />}
        </>
      )}
      {m.bundleType === 'custom' && (
        <>
          <Row k="Recipient" v={m.deliveryRecipient || '—'} />
          <Row k="Delivery" v={
            m.deliveryKind === 'site' ? (m.deliverySiteName ?? '—') :
            m.deliveryKind === 'url' ? (<a href={m.deliveryUrl ?? '#'} target="_blank" rel="noreferrer" className="underline">{m.deliveryUrl}</a>) :
            '—'
          } />
          <Row k="Price" v={m.handledInPlatform ? 'handled in-platform' :
                            m.priceCents != null ? `$${(m.priceCents / 100).toFixed(2)}` : '—'} />
        </>
      )}
      {m.bundleType === 'fansite' && (
        <>
          <Row k="Month" v={m.fansiteYear && m.fansiteMonth
            ? `${m.fansiteYear}-${String(m.fansiteMonth).padStart(2, '0')}` : '—'} />
          <Row k="Days" v={`${m.fanDays.length} day${m.fanDays.length === 1 ? '' : 's'}`} />
        </>
      )}
      {m.specialInstructions && (
        <Row k="Special instructions" v={<pre className="text-xs whitespace-pre-wrap">{m.specialInstructions}</pre>} />
      )}

      {m.bundleType === 'fansite' && m.fanDays.length > 0 && (
        <div className="mt-4">
          <div className="text-xs uppercase tracking-wider mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
            Fan-site days
          </div>
          <ul className="flex flex-col gap-1.5">
            {m.fanDays.map((d) => (
              <li key={d.dayOfMonth} className="flex items-start gap-3 text-sm">
                <span className="font-mono text-xs px-1.5 py-0.5 rounded shrink-0"
                      style={{ background: 'rgb(var(--surface-base))', minWidth: 38, textAlign: 'center' }}>
                  Day {String(d.dayOfMonth).padStart(2, '0')}
                </span>
                <span className="text-xs shrink-0 pt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
                  {d.fileCount} file{d.fileCount === 1 ? '' : 's'}
                </span>
                <span className="flex-1 min-w-0">{d.message || <em style={{ color: 'rgb(var(--surface-muted))' }}>(no message)</em>}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

