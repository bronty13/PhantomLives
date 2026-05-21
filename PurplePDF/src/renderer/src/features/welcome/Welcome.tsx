import { useEffect, useState } from 'react';
import type { RecentFile } from '../../../../shared/types';

interface Props {
  recents: RecentFile[];
  onOpen: () => void;
  onOpenPath: (path: string) => void;
  onClearRecents: () => void;
  onNewFromImages: () => void;
  onNewFromUrl: () => void;
  onNewFromOffice: () => void;
}

function relativeTime(ts: number): string {
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return 'just now';
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  if (d < 30) return `${d}d ago`;
  return new Date(ts).toLocaleDateString();
}

export default function Welcome({
  recents,
  onOpen,
  onOpenPath,
  onClearRecents,
  onNewFromImages,
  onNewFromUrl,
  onNewFromOffice
}: Props): JSX.Element {
  const [printer, setPrinter] = useState<{
    platform: string;
    installed: boolean;
    path: string;
    captureDir: string;
  } | null>(null);
  const [converter, setConverter] = useState<{ libreoffice: string | null } | null>(null);

  useEffect(() => {
    window.purplePDF
      .printerStatus()
      .then(setPrinter)
      .catch(() => undefined);
    window.purplePDF
      .converterStatus()
      .then(setConverter)
      .catch(() => undefined);
  }, []);

  const isMac = printer?.platform === 'darwin';

  const installPrinter = async (): Promise<void> => {
    await window.purplePDF.installPrinter();
    const next = await window.purplePDF.printerStatus();
    setPrinter(next);
  };

  return (
    <div className="welcome">
      <header>
        <h1>Purple PDF</h1>
        <p className="tagline">Full-featured PDF reader and editor</p>
      </header>
      <section>
        <button type="button" className="cta" onClick={onOpen}>
          Open a PDF
        </button>
        <p className="shortcut-hint">⌘O / Ctrl+O</p>
      </section>

      <section className="create-grid">
        <h2>Create a new PDF</h2>
        <div className="tile-row">
          <button type="button" className="tile" onClick={onNewFromImages}>
            <span className="tile-icon">🖼️</span>
            <span className="tile-title">From Images</span>
            <span className="tile-sub">JPG · PNG · HEIC · TIFF</span>
          </button>
          <button type="button" className="tile" onClick={onNewFromUrl}>
            <span className="tile-icon">🌐</span>
            <span className="tile-title">From Web Page</span>
            <span className="tile-sub">Capture any URL</span>
          </button>
          <button
            type="button"
            className="tile"
            onClick={onNewFromOffice}
            disabled={!converter || !converter.libreoffice}
            title={converter && !converter.libreoffice ? 'Install LibreOffice to enable' : undefined}
          >
            <span className="tile-icon">📄</span>
            <span className="tile-title">From Office Doc</span>
            <span className="tile-sub">
              {converter && !converter.libreoffice
                ? 'Needs LibreOffice'
                : 'Word · Excel · PowerPoint'}
            </span>
          </button>
        </div>
      </section>

      {printer && (
        <section className="printer-card">
          <h2>Print to Purple PDF</h2>
          {isMac ? (
            printer.installed ? (
              <>
                <p className="empty">
                  ✓ Ready. In any app, choose <strong>File → Print → PDF dropdown → Print to
                  Purple PDF</strong>.
                </p>
                <p className="meta">
                  Captures saved to <code>{printer.captureDir}</code>.
                </p>
                <button type="button" className="link" onClick={() => void installPrinter()}>
                  Reinstall
                </button>
              </>
            ) : (
              <>
                <p className="empty">
                  Not installed. Add Purple PDF to every app&apos;s Print dialog.
                </p>
                <button type="button" className="cta-secondary" onClick={() => void installPrinter()}>
                  Install Print to Purple PDF
                </button>
              </>
            )
          ) : (
            <p className="empty">
              Virtual printer on Windows is not yet available in this build.
            </p>
          )}
        </section>
      )}

      <section className="recents">
        <div className="recents-head">
          <h2>Recent files</h2>
          {recents.length > 0 && (
            <button type="button" className="link" onClick={onClearRecents}>
              Clear
            </button>
          )}
        </div>
        {recents.length === 0 ? (
          <p className="empty">No recent files yet.</p>
        ) : (
          <ul>
            {recents.map((r) => (
              <li key={r.path}>
                <button type="button" onClick={() => onOpenPath(r.path)} title={r.path}>
                  <span className="name">{r.name}</span>
                  <span className="meta">{relativeTime(r.openedAt)}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
