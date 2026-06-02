import { useEffect, useState } from 'react';
import { getSummarySettings, setSummarySettings,
         type SummarySettings as SS } from '../../data/bundles';

const MIN = 1;
const MAX = 60;
const DEFAULT = 30;

export function SummarySettings() {
  const [settings, setSettings] = useState<SS | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    getSummarySettings()
      .then((s) => { if (alive) setSettings(s); })
      .catch((e) => setStatus(`Failed to load: ${e}`));
    return () => { alive = false; };
  }, []);

  if (!settings) {
    return <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
  }

  const clamp = (n: number) => Math.max(MIN, Math.min(MAX, Math.round(n || DEFAULT)));

  const save = async () => {
    setBusy(true);
    setStatus('');
    try {
      const clean = { ...settings, thumbCount: clamp(settings.thumbCount) };
      await setSummarySettings(clean);
      setSettings(clean);
      setStatus('✓ Saved');
    } catch (e) {
      setStatus(`Save failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">SideMollySummary</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          The summary is a one-page PDF per bundle — metadata, a thumbnail grid,
          the cleaned-up video transcripts, and the full processing log.
          Generate it from a bundle's <strong>Distribute</strong> tab; it's also
          regenerated and copied to Dropbox alongside the assembled master cut.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-3">
        <div className="grid grid-cols-[180px_1fr] gap-x-3 gap-y-3 text-sm items-center">
          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Thumbnail count</label>
          <div className="flex items-center gap-2">
            <input
              type="number" min={MIN} max={MAX} step={1}
              className="sm-input w-20"
              value={settings.thumbCount}
              onChange={(e) => setSettings({ ...settings, thumbCount: Number(e.target.value) })}
            />
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
              thumbnails sampled per bundle (capped by the number of media files)
            </span>
          </div>
        </div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          This count drives <strong>both</strong> the summary PDF's grid and the
          thumbnails included in the post-bundle sent back to Molly.
        </div>

        <div className="flex justify-between items-center mt-1">
          <button
            type="button"
            className="sm-button secondary text-xs"
            onClick={() => setSettings({ ...settings, thumbCount: DEFAULT })}
          >
            Restore default ({DEFAULT})
          </button>
          <div className="flex items-center gap-3">
            {status && (
              <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>{status}</span>
            )}
            <button type="button" className="sm-button" disabled={busy} onClick={save}>
              💾 Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
