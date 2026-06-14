import { useEffect, useState } from 'react';
import { save as openSaveDialog } from '@tauri-apps/plugin-dialog';
import {
  getBundleSummaryPdfInfo,
  openBundleSummaryPdf,
  downloadBundleSummaryPdf,
  type SummaryPdfInfo,
} from '../data/bundles';

function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/**
 * The SideMolly Summary PDF that rode back in with the imported return file.
 * Self-hiding: renders nothing until it confirms a PDF is stored for this
 * bundle, so it's invisible on drafts and on bundles imported before
 * SideMolly started shipping the summary.
 */
export function BundleSummaryReport({ bundleUid }: { bundleUid: string }) {
  const [info, setInfo] = useState<SummaryPdfInfo | null>(null);
  const [status, setStatus] = useState<string>('');

  useEffect(() => {
    let alive = true;
    getBundleSummaryPdfInfo(bundleUid)
      .then((i) => { if (alive) setInfo(i); })
      .catch(() => { /* non-fatal — just don't show the section */ });
    return () => { alive = false; };
  }, [bundleUid]);

  if (!info) return null;

  async function openReport() {
    try {
      await openBundleSummaryPdf(bundleUid);
    } catch (e) {
      setStatus(`Couldn't open: ${String(e)}`);
    }
  }

  async function download() {
    if (!info) return;
    try {
      const targetPath = await openSaveDialog({ defaultPath: info.filename || 'summary.pdf' });
      if (!targetPath) return;
      await downloadBundleSummaryPdf(bundleUid, targetPath);
      setStatus('Saved a copy.');
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  return (
    <section className="pretty-card space-y-2">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="text-sm font-semibold">📄 Summary report</div>
          <div className="text-xs opacity-60 truncate">
            {info.filename} · {fmtSize(info.sizeBytes)} · from SideMolly
          </div>
        </div>
        <div className="flex gap-2 shrink-0">
          <button type="button" onClick={openReport} className="pretty-button secondary text-xs">
            Open report
          </button>
          <button type="button" onClick={download} className="pretty-button secondary text-xs">
            ⬇ Download
          </button>
        </div>
      </div>
      {status && <div className="text-xs opacity-60">{status}</div>}
    </section>
  );
}
