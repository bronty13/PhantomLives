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
  errors: { id: string; message: string }[];
}

const REQUIRED_COLUMNS = ['id', 'persona', 'title'] as const;
const YIELD_EVERY = 25; // give the event loop a tick to repaint the progress counter

export function MasterClipperImport({ personas, onDone }: Props) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [stage, setStage] = useState<Stage>('pick');
  const [parsed, setParsed] = useState<ParsedFile | null>(null);
  const [mapping, setMapping] = useState<Record<string, string>>({}); // sourcePersona -> mollyPersona code or ''
  const [report, setReport] = useState<RunReport | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<{ done: number; total: number; inserted: number; updated: number; skipped: number }>({
    done: 0,
    total: 0,
    inserted: 0,
    updated: 0,
    skipped: 0,
  });

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
    setError(null);
    setProgress({ done: 0, total: parsed.rows.length, inserted: 0, updated: 0, skipped: 0 });

    let inserted = 0, updated = 0, skipped = 0;
    const errors: { id: string; message: string }[] = [];

    try {
      for (let i = 0; i < parsed.rows.length; i++) {
        const r = parsed.rows[i];
        const id = (r.id ?? '').trim();
        const sourcePersona = (r.persona ?? '').trim();
        // Resolve the persona:
        //   - CSV row has no persona at all → import with null persona
        //     (these rows don't appear in the mapping UI; legacy behavior).
        //   - source persona is mapped to '' → user picked "skip rows with
        //     this persona" → skip the row entirely (count as skipped).
        //   - source persona is mapped to a Molly code → use that code.
        const mappedTo = sourcePersona === '' ? null : mapping[sourcePersona];
        const isExplicitSkip = sourcePersona !== '' && mappedTo === '';

        if (!id || isExplicitSkip) {
          skipped++;
        } else {
          const clip: Omit<Clip, 'mollyNotesHtml' | 'importedAt'> = {
            id,
            // Legacy columns kept on the schema for old data; not imported anymore
            // and not surfaced in the UI. See CHANGELOG 1.6.0.
            externalClipId: '',
            personaCode:  mappedTo || null,
            title:        (r.title ?? '').trim(),
            status:       (r.status ?? '').trim(),
            contentDate:  (r.content_date ?? '').trim() || null,
            goLiveDate:   (r.go_live_date ?? '').trim() || null,
            length:       (r.length ?? '').trim(),
            price:        (r.price ?? '').trim(),
            categories:   (r.categories ?? '').trim(),
            keywords:     '',
            performers:   '',
            notes:        r.notes ?? '',
          };
          try {
            const result = await upsertClip(clip);
            if (result === 'inserted') inserted++; else updated++;
          } catch (e) {
            const message = e instanceof Error ? e.message : String(e);
            console.warn('upsert failed', id, e);
            errors.push({ id, message });
            skipped++;
          }
        }
        const done = i + 1;
        // Update progress every row, but yield to the event loop every
        // YIELD_EVERY rows so React can actually repaint the counter.
        setProgress({ done, total: parsed.rows.length, inserted, updated, skipped });
        if (done % YIELD_EVERY === 0) {
          await new Promise((resolve) => setTimeout(resolve, 0));
        }
      }
    } finally {
      // Log even if the loop threw — and never leave the UI stuck on "running".
      try {
        await logImport({
          sourceFile: parsed.filename,
          rowsTotal: parsed.rows.length,
          rowsInserted: inserted,
          rowsUpdated: updated,
          rowsSkipped: skipped,
          note: errors.length > 0 ? `${errors.length} row error(s) — see console` : '',
        });
      } catch (e) {
        console.warn('logImport failed', e);
      }
      setReport({ inserted, updated, skipped, total: parsed.rows.length, errors });
      setStage('done');
      try {
        await onDone();
      } catch (e) {
        console.warn('onDone refresh failed', e);
      }
    }
  }

  const distinctSourcePersonas = useMemo(() => {
    if (!parsed) return [];
    return [...new Set(parsed.rows.map((r) => (r.persona ?? '').trim()).filter(Boolean))];
  }, [parsed]);

  const previewRows = useMemo(() => parsed?.rows.slice(0, 5) ?? [], [parsed]);
  // Empty-string is a legitimate value here: it means "skip rows with this
  // source persona" (matches the placeholder option). Mapping is always
  // initialized for every distinct source persona on file load, so the
  // only thing we actually need to guard against is `undefined`.
  const allMapped = distinctSourcePersonas.every((src) => mapping[src] !== undefined);
  // How many CSV rows would be imported vs. skipped under the current
  // mapping. Mirrors run()'s "explicit skip" semantic: a row is skipped
  // when its source persona is non-empty AND mapped to '' (i.e. the user
  // picked "skip rows with this persona"). Rows with an empty persona in
  // the CSV are NOT counted as skips here; they still import with
  // personaCode = null. The pre-flight count won't catch id-missing rows
  // (those also skip), but those are rare and surface in the final report.
  const rowsToSkip = parsed
    ? parsed.rows.filter((r) => {
        const sp = (r.persona ?? '').trim();
        return sp !== '' && mapping[sp] === '';
      }).length
    : 0;
  const rowsToImport = (parsed?.rows.length ?? 0) - rowsToSkip;

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
            Expected columns (from MasterClipper's CSV export): <span className="font-mono">id, persona, title, status, content_date, go_live_date, length, price, categories, notes</span>. Other columns (external_clip_id, keywords, performers) are ignored.
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

          <div className="flex items-center gap-2 justify-end">
            {parsed && (
              <span className="text-xs opacity-60">
                {rowsToImport} to import · {rowsToSkip} to skip
              </span>
            )}
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
        <div className="space-y-2">
          <div className="text-sm opacity-80">
            ⏳ Importing… <strong>{progress.done}</strong> of {progress.total}
            {' · '}{progress.inserted} added, {progress.updated} updated{progress.skipped > 0 && <>, {progress.skipped} skipped</>}
          </div>
          <div className="h-2 rounded-full bg-black/5 overflow-hidden">
            <div
              className="h-full rounded-full transition-all"
              style={{
                width: `${progress.total ? (progress.done / progress.total) * 100 : 0}%`,
                background: 'rgb(var(--persona-accent))',
              }}
            />
          </div>
          <div className="text-xs opacity-60">Don't close Molly until this finishes.</div>
        </div>
      )}

      {stage === 'done' && report && (
        <div className="space-y-2">
          <div className="text-sm">
            ✨ Done. <strong>{report.inserted}</strong> added, <strong>{report.updated}</strong> updated, <strong>{report.skipped}</strong> skipped (out of {report.total}).
          </div>
          {report.errors.length > 0 && (
            <details className="text-xs">
              <summary className="cursor-pointer opacity-70">{report.errors.length} row error{report.errors.length === 1 ? '' : 's'} (click to expand)</summary>
              <ul className="mt-1 space-y-0.5 max-h-40 overflow-y-auto font-mono">
                {report.errors.slice(0, 50).map((err, idx) => (
                  <li key={idx}><strong>{err.id}</strong>: {err.message}</li>
                ))}
                {report.errors.length > 50 && <li className="opacity-60">…and {report.errors.length - 50} more</li>}
              </ul>
            </details>
          )}
          <button type="button" className="pretty-button secondary" onClick={() => { setParsed(null); setReport(null); setStage('pick'); }}>
            Import another file
          </button>
        </div>
      )}
    </div>
  );
}
