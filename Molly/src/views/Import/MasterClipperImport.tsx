import { useMemo, useRef, useState } from 'react';
import { parseCsvToObjects } from '../../lib/csv';
import { logImport, upsertClip, type Clip } from '../../data/clips';
import { type Persona } from '../../data/personas';

interface Props {
  personas: Persona[];
  onDone: () => void | Promise<void>;
}

type Stage = 'pick' | 'map' | 'preview' | 'running' | 'done';

interface ParsedFile {
  filename: string;
  header: string[];
  rows: Record<string, string>[];
}

interface RunReport {
  inserted: number;
  updated: number;
  skipped: number;
  total: number;
}

const REQUIRED_COLUMNS = ['id', 'persona', 'title'] as const;

export function MasterClipperImport({ personas, onDone }: Props) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [stage, setStage] = useState<Stage>('pick');
  const [parsed, setParsed] = useState<ParsedFile | null>(null);
  const [mapping, setMapping] = useState<Record<string, string>>({}); // sourcePersona -> mollyPersona code or ''
  const [report, setReport] = useState<RunReport | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onFileChosen(file: File) {
    try {
      const text = await file.text();
      const { header, rows } = parseCsvToObjects(text);
      const missing = REQUIRED_COLUMNS.filter((c) => !header.includes(c));
      if (missing.length > 0) {
        setError(`That doesn't look like a MasterClipper export. Missing columns: ${missing.join(', ')}.`);
        return;
      }
      setError(null);
      setParsed({ filename: file.name, header, rows });

      const distinctSourcePersonas = [...new Set(rows.map((r) => (r.persona ?? '').trim()).filter(Boolean))];
      const guess: Record<string, string> = {};
      for (const src of distinctSourcePersonas) {
        const exact = personas.find((p) => p.code.toLowerCase() === src.toLowerCase());
        guess[src] = exact?.code ?? '';
      }
      setMapping(guess);
      setStage('map');
    } catch (e) {
      setError(`Couldn't read file: ${String(e)}`);
    }
  }

  async function run() {
    if (!parsed) return;
    setStage('running');
    let inserted = 0, updated = 0, skipped = 0;
    for (const r of parsed.rows) {
      const id = (r.id ?? '').trim();
      if (!id) { skipped++; continue; }
      const sourcePersona = (r.persona ?? '').trim();
      const personaCode = mapping[sourcePersona] || null;
      const clip: Omit<Clip, 'mollyNotesHtml' | 'importedAt'> = {
        id,
        externalClipId: (r.external_clip_id ?? '').trim(),
        personaCode,
        title:        (r.title ?? '').trim(),
        status:       (r.status ?? '').trim(),
        contentDate:  (r.content_date ?? '').trim() || null,
        goLiveDate:   (r.go_live_date ?? '').trim() || null,
        length:       (r.length ?? '').trim(),
        price:        (r.price ?? '').trim(),
        categories:   (r.categories ?? '').trim(),
        keywords:     (r.keywords ?? '').trim(),
        performers:   (r.performers ?? '').trim(),
        notes:        r.notes ?? '',
      };
      try {
        const result = await upsertClip(clip);
        if (result === 'inserted') inserted++; else updated++;
      } catch (e) {
        console.warn('upsert failed', id, e);
        skipped++;
      }
    }
    await logImport({
      sourceFile: parsed.filename,
      rowsTotal: parsed.rows.length,
      rowsInserted: inserted,
      rowsUpdated: updated,
      rowsSkipped: skipped,
      note: '',
    });
    setReport({ inserted, updated, skipped, total: parsed.rows.length });
    setStage('done');
    await onDone();
  }

  const distinctSourcePersonas = useMemo(() => {
    if (!parsed) return [];
    return [...new Set(parsed.rows.map((r) => (r.persona ?? '').trim()).filter(Boolean))];
  }, [parsed]);

  const previewRows = useMemo(() => parsed?.rows.slice(0, 5) ?? [], [parsed]);
  const allMapped = distinctSourcePersonas.every((src) => mapping[src] !== undefined && mapping[src] !== '');

  return (
    <div className="pretty-card space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="display-font text-xl font-semibold persona-accent">Import from MasterClipper</h3>
          <p className="text-sm opacity-70">Drop in a `clips_*.csv` export. Re-importing the same file is safe — Molly UPSERTs on the MasterClipper UID.</p>
        </div>
        {stage !== 'pick' && stage !== 'running' && (
          <button
            type="button"
            className="pretty-button secondary"
            onClick={() => { setParsed(null); setReport(null); setStage('pick'); }}
          >
            Start over
          </button>
        )}
      </div>

      {error && <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-2">{error}</div>}

      {stage === 'pick' && (
        <div>
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
            📂 Choose CSV…
          </button>
          <p className="text-xs opacity-60 mt-2">
            Expected columns (from MasterClipper's CSV export): <span className="font-mono">id, external_clip_id, persona, title, status, content_date, go_live_date, length, price, categories, keywords, performers, notes</span>.
          </p>
        </div>
      )}

      {stage === 'map' && parsed && (
        <div className="space-y-3">
          <div className="text-sm">
            <strong>{parsed.filename}</strong> · {parsed.rows.length} row{parsed.rows.length === 1 ? '' : 's'}
          </div>

          <div>
            <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Map personas</div>
            <div className="space-y-1.5">
              {distinctSourcePersonas.length === 0 && (
                <div className="text-sm opacity-70 italic">No persona values found in the file.</div>
              )}
              {distinctSourcePersonas.map((src) => (
                <div key={src} className="flex items-center gap-2 text-sm">
                  <span className="font-mono px-2 py-0.5 rounded-md bg-black/5 min-w-[8rem]">{src}</span>
                  <span className="opacity-60">→</span>
                  <select
                    className="pretty-input flex-1"
                    value={mapping[src] ?? ''}
                    onChange={(e) => setMapping({ ...mapping, [src]: e.target.value })}
                  >
                    <option value="">(skip rows with this persona)</option>
                    {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
                  </select>
                </div>
              ))}
            </div>
          </div>

          <div className="flex gap-2 justify-end">
            <button type="button" className="pretty-button secondary" onClick={() => setStage('preview')}>Preview rows →</button>
            <button type="button" className="pretty-button" onClick={run} disabled={!allMapped}>Run import</button>
          </div>
        </div>
      )}

      {stage === 'preview' && parsed && (
        <div className="space-y-3">
          <div className="text-sm">
            Preview of the first 5 rows. Persona mapping currently:
            <ul className="mt-1">
              {distinctSourcePersonas.map((src) => (
                <li key={src} className="text-xs">
                  <span className="font-mono">{src}</span> → <span className="font-semibold">{mapping[src] || '(skip)'}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="overflow-x-auto">
            <table className="text-xs w-full">
              <thead>
                <tr className="text-left">
                  {['id', 'persona', 'title', 'status', 'go_live_date', 'length'].map((h) => (
                    <th key={h} className="px-2 py-1 font-semibold opacity-70 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {previewRows.map((r, idx) => (
                  <tr key={idx} className="border-t border-black/5">
                    <td className="px-2 py-1 font-mono">{r.id}</td>
                    <td className="px-2 py-1">{r.persona}</td>
                    <td className="px-2 py-1">{r.title}</td>
                    <td className="px-2 py-1">{r.status}</td>
                    <td className="px-2 py-1 font-mono">{r.go_live_date}</td>
                    <td className="px-2 py-1 font-mono">{r.length}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="flex gap-2 justify-end">
            <button type="button" className="pretty-button secondary" onClick={() => setStage('map')}>← Back</button>
            <button type="button" className="pretty-button" onClick={run} disabled={!allMapped}>Run import</button>
          </div>
        </div>
      )}

      {stage === 'running' && (
        <div className="text-sm opacity-80">⏳ Importing… don't close the app.</div>
      )}

      {stage === 'done' && report && (
        <div className="space-y-2">
          <div className="text-sm">
            ✨ Done. <strong>{report.inserted}</strong> added, <strong>{report.updated}</strong> updated, <strong>{report.skipped}</strong> skipped (out of {report.total}).
          </div>
          <button type="button" className="pretty-button secondary" onClick={() => { setParsed(null); setReport(null); setStage('pick'); }}>
            Import another file
          </button>
        </div>
      )}
    </div>
  );
}
