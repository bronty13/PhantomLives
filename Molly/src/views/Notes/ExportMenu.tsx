import { useRef, useState } from 'react';
import { save as saveDialog } from '@tauri-apps/plugin-dialog';
import { downloadDir, join } from '@tauri-apps/api/path';
import { invoke } from '@tauri-apps/api/core';

// html-to-docx / jspdf / html2canvas-pro / turndown are loaded lazily.
// Eager imports of these heavy libraries were causing module-evaluation
// crashes at app boot (some pull in Node-only or DOM-init code paths).
// Dynamic import isolates any failure to the click that wants the
// export, instead of nuking the whole React tree on mount.

interface Props {
  noteTitle: string;
  noteHtml: string;
  /** Optional font + paper colour applied to the exported PDF + DOCX
   *  so the print looks like Sallie's screen. */
  fontFamily?: string | null;
  paperColor?: string | null;
}

type Format = 'md' | 'docx' | 'pdf';

const DEFAULT_DIR_NAME = 'Molly notes';

function safeFilename(title: string): string {
  return title
    .replace(/[/\\:*?"<>|]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80) || 'Untitled note';
}

export function ExportMenu({ noteTitle, noteHtml, fontFamily, paperColor }: Props) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<Format | null>(null);
  const [error, setError] = useState<string | null>(null);
  const wrapRef = useRef<HTMLDivElement | null>(null);

  async function doExport(fmt: Format) {
    setOpen(false);
    setError(null);
    setBusy(fmt);
    try {
      const base = safeFilename(noteTitle);
      const defaultPath = await join(await downloadDir(), DEFAULT_DIR_NAME, `${base}.${fmt}`);
      const dest = await saveDialog({
        title: `Export as ${fmt.toUpperCase()}`,
        defaultPath,
      });
      if (!dest) { setBusy(null); return; }

      let bytes: Uint8Array;
      if (fmt === 'md') {
        bytes = new TextEncoder().encode(await renderMarkdown(noteTitle, noteHtml));
      } else if (fmt === 'docx') {
        bytes = await renderDocx(noteTitle, noteHtml, fontFamily);
      } else {
        bytes = await renderPdf(noteTitle, noteHtml, fontFamily, paperColor);
      }
      await invoke('write_note_export', { destPath: dest, bytes: Array.from(bytes) });
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="relative inline-block" ref={wrapRef}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        disabled={busy != null}
        className="pretty-button secondary text-xs"
        title="Export this note"
      >
        {busy ? `Exporting ${busy.toUpperCase()}…` : '⬇ Export'}
      </button>
      {open && (
        <div
          className="absolute right-0 top-full mt-1 z-20 bg-white rounded-2xl shadow-lg border border-black/10 py-1 min-w-[180px]"
          onMouseLeave={() => setOpen(false)}
        >
          <ExportItem icon="📝" label="Markdown (.md)" onClick={() => doExport('md')} />
          <ExportItem icon="📄" label="Word (.docx)" onClick={() => doExport('docx')} />
          <ExportItem icon="📕" label="PDF (.pdf)" onClick={() => doExport('pdf')} />
        </div>
      )}
      {error && (
        <div className="absolute right-0 top-full mt-1 z-20 bg-red-50 border border-red-200 rounded-xl px-3 py-2 text-xs text-red-700 max-w-[320px]">
          {error}
          <button type="button" onClick={() => setError(null)} className="ml-2 opacity-70 hover:opacity-100">×</button>
        </div>
      )}
    </div>
  );
}

function ExportItem({ icon, label, onClick }: { icon: string; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full text-left text-xs px-3 py-2 hover:bg-black/5 flex items-center gap-2"
    >
      <span>{icon}</span><span>{label}</span>
    </button>
  );
}

// ----- Format renderers ------------------------------------------------------

async function renderMarkdown(title: string, html: string): Promise<string> {
  const { default: TurndownService } = await import('turndown');
  const td = new TurndownService({
    headingStyle: 'atx',
    codeBlockStyle: 'fenced',
    bulletListMarker: '-',
    emDelimiter: '*',
  });
  // Preserve underline as plain text wrapped in HTML <u> tags since
  // Markdown has no native underline; pure-MD renderers will show them
  // as literals, but pandoc/MD-with-HTML viewers respect the tag.
  td.keep(['u']);
  const body = td.turndown(html);
  return `# ${title}\n\n${body}\n`;
}

async function renderDocx(title: string, html: string, fontFamily?: string | null): Promise<Uint8Array> {
  const { default: htmlToDocx } = await import('html-to-docx');
  const wrapped = wrapForExport(title, html, fontFamily ?? null, null);
  const blob = await htmlToDocx(wrapped, undefined, {
    margins: { top: 1440, right: 1440, bottom: 1440, left: 1440 }, // 1in
    title,
    creator: 'Molly',
    font: fontFamily ?? 'Calibri',
  });
  return new Uint8Array(await (blob as Blob).arrayBuffer());
}

async function renderPdf(
  title: string, html: string, fontFamily: string | null | undefined, paperColor: string | null | undefined,
): Promise<Uint8Array> {
  const { default: jsPDF } = await import('jspdf');
  const { default: html2canvas } = await import('html2canvas-pro');
  // Build a hidden off-screen element with the print-shaped layout so
  // html2canvas can render it without affecting the live editor.
  const host = document.createElement('div');
  host.style.position = 'fixed';
  host.style.left = '-10000px';
  host.style.top = '0';
  host.style.width = '794px'; // A4 @ 96 DPI
  host.style.background = paperColor ?? 'white';
  host.style.padding = '48px 56px';
  host.style.fontFamily = fontFamily ?? 'system-ui, sans-serif';
  host.style.color = '#1a1a1a';
  host.style.lineHeight = '1.6';
  host.innerHTML = `
    <h1 style="font-family:${fontFamily ?? 'inherit'}; font-size:28px; margin:0 0 18px; color:#7C3AED;">${escapeHtml(title)}</h1>
    <div class="molly-note-editor" style="font-family:${fontFamily ?? 'inherit'};">${html}</div>
  `;
  document.body.appendChild(host);
  try {
    const canvas = await html2canvas(host, { scale: 2, useCORS: true, backgroundColor: paperColor ?? '#ffffff' });
    const imgData = canvas.toDataURL('image/png');
    const pdf = new jsPDF({ unit: 'pt', format: 'a4', compress: true });
    const pageWidth = pdf.internal.pageSize.getWidth();
    const pageHeight = pdf.internal.pageSize.getHeight();
    const imgWidth = pageWidth;
    const imgHeight = (canvas.height * imgWidth) / canvas.width;
    let heightLeft = imgHeight;
    let position = 0;
    pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
    heightLeft -= pageHeight;
    while (heightLeft > 0) {
      position -= pageHeight;
      pdf.addPage();
      pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
      heightLeft -= pageHeight;
    }
    const blob = pdf.output('arraybuffer');
    return new Uint8Array(blob as ArrayBuffer);
  } finally {
    document.body.removeChild(host);
  }
}

function wrapForExport(title: string, body: string, fontFamily: string | null, paperColor: string | null): string {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head>
<body style="font-family:${fontFamily ?? 'Calibri'}; background:${paperColor ?? '#ffffff'};">
  <h1>${escapeHtml(title)}</h1>
  ${body}
</body></html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
