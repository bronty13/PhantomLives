import { useCallback, useEffect, useState } from 'react';
import {
  type ReturnFileCandidate,
  type ReturnFileImportResult,
  importReturnFile,
  listReturnFileCandidates,
  revealPostBundlesDir,
} from '../../data/bundles';

type Stage = 'picking' | 'importing' | 'done' | 'error';

interface Props {
  onClose: () => void;
  /** Called after a successful import so the parent can refresh the list. */
  onImported: () => void;
}

export function ImportReturnFileWizard({ onClose, onImported }: Props) {
  const [stage, setStage] = useState<Stage>('picking');
  const [candidates, setCandidates] = useState<ReturnFileCandidate[]>([]);
  const [loadingCandidates, setLoadingCandidates] = useState(true);
  const [result, setResult] = useState<ReturnFileImportResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoadingCandidates(true);
    try {
      const list = await listReturnFileCandidates();
      setCandidates(list);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoadingCandidates(false);
    }
  }, []);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const list = await listReturnFileCandidates();
        if (!alive) return;
        setCandidates(list);
      } catch (e) {
        if (!alive) return;
        setError(String(e));
      } finally {
        if (alive) setLoadingCandidates(false);
      }
    })();
    return () => { alive = false; };
  }, []);

  async function runImport(path: string) {
    setStage('importing');
    setError(null);
    try {
      const r = await importReturnFile(path);
      setResult(r);
      setStage('done');
      onImported();
    } catch (e: any) {
      const msg = (e && typeof e === 'object' && 'message' in e) ? String((e as any).message) : String(e);
      setError(msg);
      setStage('error');
    }
  }

  async function pickFromDisk() {
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const picked = await open({
        multiple: false,
        directory: false,
        title: 'Pick a return file (-post.zip)',
        filters: [{ name: 'Molly post-bundle', extensions: ['zip'] }],
      });
      if (!picked || typeof picked !== 'string') return;
      await runImport(picked);
    } catch (e) {
      setError(String(e));
      setStage('error');
    }
  }

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm flex items-stretch justify-end">
      <div className="bg-white w-full max-w-3xl h-full overflow-y-auto shadow-2xl flex flex-col">
        <header className="p-6 border-b border-black/5 flex items-center justify-between sticky top-0 bg-white z-10">
          <div>
            <h2 className="display-font text-xl font-semibold">📥 Import Return File</h2>
            <p className="text-xs opacity-60">
              Pull SideMolly's post-bundle ZIP back into Molly to close the round-trip.
            </p>
          </div>
          <button type="button" onClick={onClose} className="pretty-button secondary">Cancel</button>
        </header>

        {stage === 'picking' && (
          <div className="p-6 space-y-4 flex-1">
            <section className="space-y-2">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">
                  Candidates in ~/Downloads/Molly post-bundles/
                </h3>
                <button type="button" onClick={refresh} className="pretty-button secondary text-xs">
                  Refresh
                </button>
              </div>
              {loadingCandidates ? (
                <div className="opacity-60 italic">Scanning…</div>
              ) : candidates.length === 0 ? (
                <div className="pretty-card text-sm">
                  <div className="opacity-80">
                    No return files found in the default folder yet.
                  </div>
                  <div className="opacity-60 text-xs mt-1">
                    After SideMolly composes a post-bundle, it lands here. You can also pick a file from disk below.
                  </div>
                </div>
              ) : (
                <ul className="space-y-2">
                  {candidates.map((c) => (
                    <li
                      key={c.path}
                      className="pretty-card flex items-center gap-3"
                    >
                      <div className="flex-1 min-w-0">
                        <div className="flex items-baseline gap-2">
                          <span className="font-mono text-xs opacity-60">{c.bundleUid}</span>
                          <span className="text-xs uppercase tracking-wider opacity-50">{c.bundleType}</span>
                          {c.alreadyImported && (
                            <span className="text-[11px] font-semibold px-1.5 py-0.5 rounded-full" style={{ background: '#F1F5F9', color: '#475569' }}>
                              already imported
                            </span>
                          )}
                          {!c.bundleKnown && (
                            <span className="text-[11px] font-semibold px-1.5 py-0.5 rounded-full" style={{ background: '#FEF3C7', color: '#92400E' }}>
                              unknown bundle
                            </span>
                          )}
                        </div>
                        <div className="truncate font-medium" title={c.filename}>{c.filename}</div>
                        <div className="text-xs opacity-60 flex flex-wrap gap-x-3">
                          <span>composed: {c.composedAt.slice(0, 19).replace('T', ' ')}</span>
                          <span>{(c.sizeBytes / 1024).toFixed(1)} KB</span>
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => runImport(c.path)}
                        disabled={!c.bundleKnown}
                        className="pretty-button"
                        title={c.bundleKnown ? 'Import this return file' : "The bundle UID doesn't match anything in Molly"}
                      >
                        {c.alreadyImported ? 'Re-import' : 'Import'}
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </section>

            <section className="space-y-2 border-t border-black/5 pt-4">
              <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">Other</h3>
              <div className="flex gap-2">
                <button type="button" onClick={pickFromDisk} className="pretty-button secondary">
                  📂 Pick from disk…
                </button>
                <button type="button" onClick={() => revealPostBundlesDir()} className="pretty-button secondary">
                  Reveal folder in Finder
                </button>
              </div>
            </section>

            {error && (
              <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
            )}
          </div>
        )}

        {stage === 'importing' && (
          <div className="p-12 flex flex-col items-center gap-3 opacity-80">
            <div className="display-font text-lg">Importing return file…</div>
            <div className="text-xs opacity-60">Parsing report · matching clips · stamping bundle</div>
          </div>
        )}

        {stage === 'done' && result && (
          <ImportResult result={result} onClose={onClose} onImportAnother={() => {
            setResult(null);
            setError(null);
            setStage('picking');
            refresh();
          }} />
        )}

        {stage === 'error' && (
          <div className="p-6 space-y-3">
            <div className="bg-red-50 border border-red-200 rounded-2xl p-4 text-sm text-red-800 whitespace-pre-wrap">
              {error}
            </div>
            <div className="flex gap-2">
              <button type="button" onClick={() => { setError(null); setStage('picking'); }} className="pretty-button secondary">
                Back to candidates
              </button>
              <button type="button" onClick={onClose} className="pretty-button secondary ml-auto">Close</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ImportResult({
  result,
  onClose,
  onImportAnother,
}: {
  result: ReturnFileImportResult;
  onClose: () => void;
  onImportAnother: () => void;
}) {
  const isFansite = result.bundleType === 'fansite';
  return (
    <div className="p-6 space-y-4">
      {result.wasDuplicate && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl px-3 py-2 text-sm text-amber-900">
          This return file was already imported. Showing the prior result.
        </div>
      )}
      {result.reportedBundleType && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl px-3 py-2 text-sm text-amber-900">
          ⚠️ Type mismatch — Molly has this bundle stored as <strong>{result.bundleType}</strong>,
          but SideMolly's return file says <strong>{result.reportedBundleType}</strong>. The import went through; double-check the postings below look right, and consider re-syncing one side to match.
        </div>
      )}
      <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-4 space-y-1">
        <div className="text-lg font-semibold text-emerald-800">
          ✅ {result.wasDuplicate ? 'Already imported' : 'Imported.'}
        </div>
        <div className="text-xs opacity-70 font-mono">
          {result.bundleUid} · {result.bundleType}
        </div>
        <div className="text-sm">
          {result.bundleAlreadyPurged
            ? 'Original bundle ZIP was already cleaned up.'
            : result.deleteAfter
              ? `Bundle scheduled for cleanup on ${result.deleteAfter.slice(0, 10)}.`
              : ''}
        </div>
      </div>

      <section className="space-y-2">
        <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">
          Postings ({result.postings.length})
        </h3>
        {result.postings.length === 0 ? (
          <div className="opacity-60 italic text-sm">No targets in this return file.</div>
        ) : (
          <ul className="space-y-2">
            {result.postings.map((p) => (
              <li key={p.id} className="rounded-xl border border-black/5 bg-white/60 p-3 space-y-1.5">
                <div className="flex items-center gap-2 flex-wrap text-sm">
                  <span className="font-medium">{p.targetName}</span>
                  <StatePill state={p.state} />
                  {p.fansiteDay != null && (
                    <span className="text-xs opacity-60">Day {String(p.fansiteDay).padStart(2, '0')}</span>
                  )}
                  {p.postedAt && <span className="text-xs opacity-60 font-mono">{p.postedAt.slice(0, 19).replace('T', ' ')}</span>}
                </div>
                {p.postedUrl && (
                  <a href={p.postedUrl} target="_blank" rel="noreferrer" className="text-xs font-mono text-blue-700 break-all underline">
                    {p.postedUrl}
                  </a>
                )}
                {p.notes && <div className="text-xs opacity-80 italic">📝 {p.notes}</div>}
                {p.bodyOverride && (
                  <details className="text-xs opacity-80">
                    <summary className="cursor-pointer">Body override</summary>
                    <pre className="whitespace-pre-wrap bg-pink-50 rounded p-2 mt-1">{p.bodyOverride}</pre>
                  </details>
                )}
                {p.files.length > 0 && (
                  <ul className="text-xs opacity-80 mt-1 pl-3 border-l-2 border-black/5 space-y-0.5">
                    {p.files.map((f) => (
                      <li key={f.relpath} className="flex items-baseline gap-2">
                        <span className="font-mono truncate flex-1" title={f.relpath}>{f.relpath}</span>
                        {!isFansite && (
                          f.clipId ? (
                            <span className="text-emerald-700">→ clip {f.clipTitle ?? f.clipId}</span>
                          ) : (
                            <span className="text-amber-700">no clip match</span>
                          )
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      {!isFansite && result.totalFileCount > 0 && (
        <section className="space-y-1">
          <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">
            Clip writeback
          </h3>
          <div className="text-sm">
            <strong>{result.matchedFileCount}</strong> of {result.totalFileCount} files matched to a clip by filename.
            {result.matchedFileCount < result.totalFileCount && (
              <span className="opacity-70"> Unmatched files are still recorded under the posting; you can fix them by renaming or re-importing.</span>
            )}
          </div>
        </section>
      )}

      {isFansite && (
        <section className="space-y-1">
          <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">FanSite</h3>
          <div className="text-sm opacity-70">
            FanSite postings are logged but not written back to clips (calendar days aren't clips).
          </div>
        </section>
      )}

      <div className="flex gap-2 pt-2 border-t border-black/5">
        <button type="button" onClick={onImportAnother} className="pretty-button secondary">Import another</button>
        <button type="button" onClick={onClose} className="pretty-button ml-auto">Done</button>
      </div>
    </div>
  );
}

function StatePill({ state }: { state: string }) {
  let bg = '#E5E7EB', color = '#374151';
  if (state === 'posted') { bg = '#DCFCE7'; color = '#166534'; }
  else if (state === 'scheduled') { bg = '#DBEAFE'; color = '#1E40AF'; }
  else if (state === 'pending') { bg = '#FEE7F0'; color = '#9D174D'; }
  else if (state === 'skipped') { bg = '#F1F5F9'; color = '#475569'; }
  return (
    <span className="text-[11px] font-semibold px-1.5 py-0.5 rounded-full" style={{ background: bg, color }}>
      {state}
    </span>
  );
}
