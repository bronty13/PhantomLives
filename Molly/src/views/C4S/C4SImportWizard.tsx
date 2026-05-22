import { useMemo, useRef, useState } from 'react';
import { parsePipeCsvToObjects } from '../../lib/csvPipe';
import {
  detectPersonaFromRows,
  personaDisplayName,
  type PersonaCode,
} from '../../lib/c4sClassify';
import {
  c4sLastImportFor,
  replaceC4SClips,
  type C4SClipDto,
  type ReplaceResult,
} from '../../data/c4sClips';

interface Props {
  onClose: () => void;
  onImported?: (result: ReplaceResult) => void | Promise<void>;
}

type Stage = 'pick' | 'confirm' | 'running' | 'done' | 'error';

interface ParsedFile {
  filename: string;
  header: string[];
  rows: Record<string, string>[];
}

interface SkippedRow {
  index: number;
  reason: string;
}

const REQUIRED_COLUMNS = ['Clip Status', 'Clip ID', 'Clip Title', 'Performers'] as const;

function parsePrice(raw: string): number | null {
  if (!raw) return null;
  const cleaned = raw.replace(/[$,\s]/g, '');
  if (cleaned === '') return null;
  const n = Number(cleaned);
  if (Number.isNaN(n)) return null;
  return Math.round(n * 100);
}

function parseInt0(raw: string): number | null {
  if (!raw || !raw.trim()) return null;
  const n = parseInt(raw.replace(/[,\s]/g, ''), 10);
  return Number.isNaN(n) ? null : n;
}

function normalize(parsed: ParsedFile): { rows: C4SClipDto[]; skipped: SkippedRow[] } {
  const out: C4SClipDto[] = [];
  const skipped: SkippedRow[] = [];
  parsed.rows.forEach((r, i) => {
    const clipId = (r['Clip ID'] ?? '').trim();
    const title = (r['Clip Title'] ?? '').trim();
    if (!clipId) {
      skipped.push({ index: i, reason: 'missing Clip ID' });
      return;
    }
    if (!title) {
      skipped.push({ index: i, reason: 'missing Clip Title' });
      return;
    }
    out.push({
      clipId,
      clipStatus: (r['Clip Status'] ?? '').trim(),
      clipTrackingTag: (r['Clip Tracking Tag'] ?? '').trim(),
      clipTitle: title,
      clipDescription: r['Clip Description'] ?? '',
      categories: (r['Categories'] ?? '').trim(),
      keywords: (r['Keywords'] ?? '').trim(),
      clipFilename: (r['Clip Filename'] ?? '').trim(),
      clipThumbnail: (r['Clip Thumbnail Filename'] ?? '').trim(),
      clipPreview: (r['Clip Preview Filename'] ?? '').trim(),
      performers: (r['Performers'] ?? '').trim(),
      priceCents: parsePrice(r['Price'] ?? ''),
      salesCount: parseInt0(r['Sales # (total sales even after refunds)'] ?? ''),
      income6moCents: parsePrice(r['Income for last 6 months $ (creator’s income excluding C4S %)'] ?? ''),
    });
  });
  return { rows: out, skipped };
}

export function C4SImportWizard({ onClose, onImported }: Props) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [stage, setStage] = useState<Stage>('pick');
  const [parsed, setParsed] = useState<ParsedFile | null>(null);
  const [persona, setPersona] = useState<PersonaCode | null>(null);
  const [detectedPersona, setDetectedPersona] = useState<PersonaCode | null>(null);
  const [existingCount, setExistingCount] = useState<number | null>(null);
  const [normalized, setNormalized] = useState<C4SClipDto[]>([]);
  const [skipped, setSkipped] = useState<SkippedRow[]>([]);
  const [result, setResult] = useState<ReplaceResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onFileChosen(file: File) {
    try {
      const text = await file.text();

      // Fast-fail diagnostics BEFORE we hand the bytes to the parser —
      // most "won't import" support tickets come from picking the wrong
      // file (Excel save-as, CSV with commas, an old MasterClipper
      // export, etc.). Telling the user *which* mistake they made is
      // worth ten "doesn't look like a Clips4Sale export" messages.
      if (text.charCodeAt(0) === 0x50 && text.charCodeAt(1) === 0x4b) {
        // ZIP magic bytes 'PK' — this is .xlsx, .zip, .docx, or a C4S
        // Excel export that should have been saved as CSV.
        setError(
          `This looks like an Excel (.xlsx) or zipped file, not a CSV. 💕\n\n` +
            `In C4S → Manage Clips, scroll to the bottom and look for the "Export to CSV" button (not "Export to Excel"). ` +
            `Save that file to Downloads and try again.`,
        );
        return;
      }
      if (!text.includes('|') && text.includes(',')) {
        setError(
          `This file uses commas, not pipes — C4S has a separate CSV export button you need to use. 💕\n\n` +
            `Look for the "Export to CSV" button at the bottom of Manage Clips. The first line should start with ` +
            `"Clip Status"|"Clip ID"|… — yours starts with:\n${text.slice(0, 120)}…`,
        );
        return;
      }

      const { header, rows } = parsePipeCsvToObjects(text);
      const missing = REQUIRED_COLUMNS.filter((c) => !header.includes(c));
      if (missing.length > 0) {
        const found = header.length === 0
          ? '(no header row found — file may be empty)'
          : header.length === 1
            ? `(one giant column — pipe delimiter probably wasn't recognized. First line: ${header[0].slice(0, 120)}…)`
            : `Found ${header.length} column${header.length === 1 ? '' : 's'}: ${header.slice(0, 8).map((h) => `"${h}"`).join(', ')}${header.length > 8 ? `…` : ''}`;
        setError(
          `That doesn't look like a Clips4Sale clip export.\n\n` +
            `Missing required columns: ${missing.join(', ')}.\n\n` +
            `${found}\n\n` +
            `In C4S → Manage Clips → look for the "Export to CSV" button at the bottom. The filename should look like ` +
            `coc_clips-export-YYYY-MM-DD_HH-MM-SS.csv. The file you picked was: ${file.name} (${file.size.toLocaleString()} bytes).`,
        );
        return;
      }
      setError(null);
      const next: ParsedFile = { filename: file.name, header, rows };
      setParsed(next);
      const guess = detectPersonaFromRows(rows);
      setDetectedPersona(guess);
      setPersona(guess);
      const { rows: normRows, skipped: normSkipped } = normalize(next);
      setNormalized(normRows);
      setSkipped(normSkipped);
      if (guess) {
        try {
          const last = await c4sLastImportFor(guess);
          setExistingCount(last?.rowCount ?? 0);
        } catch {
          setExistingCount(null);
        }
      } else {
        setExistingCount(null);
      }
      setStage('confirm');
    } catch (e) {
      setError(`Couldn't read file: ${String(e)}`);
    }
  }

  async function onPersonaPicked(p: PersonaCode) {
    setPersona(p);
    try {
      const last = await c4sLastImportFor(p);
      setExistingCount(last?.rowCount ?? 0);
    } catch {
      setExistingCount(null);
    }
  }

  async function runImport() {
    if (!parsed || !persona) return;
    setStage('running');
    setError(null);
    try {
      const r = await replaceC4SClips(persona, parsed.filename, normalized);
      setResult(r);
      setStage('done');
      try {
        await onImported?.(r);
      } catch (e) {
        console.warn('onImported refresh failed', e);
      }
    } catch (e) {
      setError(String(e));
      setStage('error');
    }
  }

  const performersSample = useMemo(() => {
    if (!parsed) return '';
    for (const r of parsed.rows) {
      const p = (r['Performers'] ?? '').trim();
      if (p) return p;
    }
    return '';
  }, [parsed]);

  return (
    <div
      className="fixed inset-0 z-30 flex items-center justify-center bg-black/30 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-3xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl"
        style={{ borderTop: '8px solid rgb(var(--persona-accent))' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-3 mb-3">
          <div>
            <h3 className="display-font text-xl font-bold persona-accent">✨ Import C4S CSV</h3>
            <p className="text-sm opacity-70">
              Pipe-delimited Clips4Sale export. Each import replaces the entire store snapshot atomically.
            </p>
          </div>
          {stage !== 'running' && (
            <button type="button" className="pretty-button secondary" onClick={onClose}>Close</button>
          )}
        </div>

        {error && (
          <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3 mb-3 whitespace-pre-wrap">
            {error}
          </div>
        )}

        {stage === 'pick' && (
          <div className="space-y-2">
            <input
              ref={fileInput}
              type="file"
              accept=".csv,text/csv"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) onFileChosen(f);
                e.target.value = '';
              }}
            />
            <button type="button" className="pretty-button" onClick={() => fileInput.current?.click()}>
              📂 Choose C4S export…
            </button>
            <p className="text-xs opacity-60">
              Look for <span className="font-mono">coc_clips-export-…csv</span> or{' '}
              <span className="font-mono">poa_clips-export-…csv</span> in your Downloads folder.
            </p>
          </div>
        )}

        {stage === 'confirm' && parsed && (
          <div className="space-y-3">
            <div className="p-3 rounded-2xl border border-black/5 bg-black/[0.02]">
              <div className="text-sm">
                🔍 Found <strong>{parsed.rows.length}</strong> row{parsed.rows.length === 1 ? '' : 's'} in{' '}
                <span className="font-mono text-xs">{parsed.filename}</span>.
              </div>
              {detectedPersona ? (
                <div className="text-sm opacity-80 mt-1">
                  Performers field says <strong>{performersSample}</strong> — looks like a{' '}
                  <strong>{detectedPersona === 'CoC' ? 'CoC (Curse Of Curves)' : 'PoA (Princess of Addiction)'}</strong> export.
                </div>
              ) : (
                <div className="text-sm opacity-80 mt-1">
                  Couldn't auto-detect the store from <span className="font-mono">Performers</span> — pick one below.
                </div>
              )}
              {skipped.length > 0 && (
                <div className="text-xs mt-2" style={{ color: '#B45309' }}>
                  ⚠ {skipped.length} row{skipped.length === 1 ? '' : 's'} will be skipped
                  (missing Clip ID or Title) — full list below.
                </div>
              )}
            </div>

            <div className="text-xs uppercase tracking-wider opacity-60">Import as</div>
            <div className="flex gap-2">
              {(['CoC', 'PoA'] as const).map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => onPersonaPicked(p)}
                  className="pretty-button"
                  style={{
                    background: persona === p ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.6)',
                    color: persona === p ? 'white' : 'rgb(var(--persona-text))',
                    border: '1px solid rgb(var(--persona-primary) / 0.45)',
                  }}
                >
                  {p === 'CoC' ? 'Curse Of Curves (CoC)' : 'Princess of Addiction (PoA)'}
                  {detectedPersona === p && <span className="opacity-60 text-xs ml-2">(auto-detected)</span>}
                </button>
              ))}
            </div>

            {persona && (
              <div className="text-xs opacity-70 italic">
                This will <strong>replace</strong> all existing {persona} C4S data
                {existingCount != null && existingCount > 0 ? ` (currently ${existingCount} rows)` : ''}.
                The other persona's data is untouched.
              </div>
            )}

            {skipped.length > 0 && (
              <details className="text-xs">
                <summary className="cursor-pointer opacity-70">
                  {skipped.length} skipped row{skipped.length === 1 ? '' : 's'} (click to expand)
                </summary>
                <ul className="mt-1 space-y-0.5 max-h-40 overflow-y-auto font-mono">
                  {skipped.slice(0, 100).map((s) => (
                    <li key={s.index}>row {s.index + 2}: {s.reason}</li>
                  ))}
                  {skipped.length > 100 && (
                    <li className="opacity-60">…and {skipped.length - 100} more</li>
                  )}
                </ul>
              </details>
            )}

            <div className="flex gap-2 justify-end">
              <button type="button" className="pretty-button secondary" onClick={() => setStage('pick')}>
                ← Pick a different file
              </button>
              <button
                type="button"
                className="pretty-button"
                onClick={runImport}
                disabled={!persona || normalized.length === 0}
              >
                Yes, import as {persona ?? '…'}
              </button>
            </div>
          </div>
        )}

        {stage === 'running' && (
          <div className="space-y-2">
            <div className="text-sm">
              ⏳ Replacing {persona} snapshot — {normalized.length} clips…
            </div>
            <div className="h-2 rounded-full bg-black/5 overflow-hidden">
              <div
                className="h-full rounded-full transition-all"
                style={{ width: '60%', background: 'rgb(var(--persona-accent))' }}
              />
            </div>
            <div className="text-xs opacity-60">Don't close Molly until this finishes.</div>
          </div>
        )}

        {stage === 'done' && result && (
          <div className="space-y-3">
            <div className="p-3 rounded-2xl border border-black/5"
                 style={{ background: result.matches ? '#ECFDF5' : '#FFFBEB' }}>
              <div className="text-base">
                {result.matches ? '🎉' : '⚠'} Imported{' '}
                <strong>{result.insertedCount}</strong> of <strong>{result.expectedCount}</strong>{' '}
                {persona && personaDisplayName(persona)} clips.
                {' '}
                {result.matches
                  ? '✓ Row count verified.'
                  : '⚠ Row count mismatch — please re-export and try again.'}
              </div>
              {skipped.length > 0 && (
                <div className="text-xs opacity-70 mt-1">
                  {skipped.length} row{skipped.length === 1 ? '' : 's'} were skipped during parse (missing ID or title).
                </div>
              )}
              {result.deletedCount > 0 && (
                <div className="text-xs opacity-70 mt-1">
                  Replaced {result.deletedCount} prior {persona} row{result.deletedCount === 1 ? '' : 's'}.
                </div>
              )}
            </div>

            {skipped.length > 0 && (
              <details className="text-xs">
                <summary className="cursor-pointer opacity-70">Show skipped rows</summary>
                <ul className="mt-1 space-y-0.5 max-h-40 overflow-y-auto font-mono">
                  {skipped.slice(0, 100).map((s) => (
                    <li key={s.index}>row {s.index + 2}: {s.reason}</li>
                  ))}
                  {skipped.length > 100 && (
                    <li className="opacity-60">…and {skipped.length - 100} more</li>
                  )}
                </ul>
              </details>
            )}

            <div className="flex gap-2 justify-end">
              <button type="button" className="pretty-button secondary" onClick={() => {
                setParsed(null); setPersona(null); setNormalized([]); setSkipped([]); setResult(null);
                setStage('pick');
              }}>
                Import another file
              </button>
              <button type="button" className="pretty-button" onClick={onClose}>Done</button>
            </div>
          </div>
        )}

        {stage === 'error' && (
          <div className="flex gap-2 justify-end">
            <button type="button" className="pretty-button secondary" onClick={() => setStage('confirm')}>
              ← Back
            </button>
            <button type="button" className="pretty-button" onClick={onClose}>Close</button>
          </div>
        )}
      </div>
    </div>
  );
}
