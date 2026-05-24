import { useEffect, useState } from 'react';
import { getAutoAssemblySettings, getDeepFilterNetStatus, setAutoAssemblySettings,
         type AutoAssemblySettings as AAS,
         type DeepFilterNetStatus } from '../../data/bundles';

export function AutoAssemblySettings() {
  const [settings, setSettings] = useState<AAS | null>(null);
  const [dfn, setDfn] = useState<DeepFilterNetStatus | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    Promise.all([
      getAutoAssemblySettings(),
      getDeepFilterNetStatus().catch(() => null),
    ]).then(([s, d]) => {
      if (!alive) return;
      setSettings(s);
      setDfn(d);
    }).catch((e) => setStatus(`Failed to load: ${e}`));
    return () => { alive = false; };
  }, []);

  if (!settings) {
    return <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
  }

  const update = (patch: Partial<AAS>) => setSettings({ ...settings, ...patch });

  const save = async () => {
    setBusy(true);
    setStatus('');
    try {
      await setAutoAssemblySettings(settings);
      setStatus('✓ Saved');
    } catch (e) {
      setStatus(`Save failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const resetDefaults = () => setSettings({
    targetWidth: 1920, targetHeight: 1080, targetFps: 30,
    xfadeDurationSecs: 1.0, titleDurationSecs: 10.0,
    audioEnhanceEnabled: true, deepfilternetEnabled: false,
  });

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">Auto-Assembly defaults</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          Read at the moment you click <strong>🎞 Auto-assemble master</strong>
          on a bundle's Edit tab. The pipeline composes title card →
          normalize+watermark+audio for each clip → xfade chain →
          fade-to-black master. Defaults match the Phase 4.5 spec —
          1920×1080 @ 30fps, 1.0s xfade, 10s title.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-3">
        <div className="grid grid-cols-[180px_1fr] gap-x-3 gap-y-3 text-sm items-center">
          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Target resolution</label>
          <div className="flex items-center gap-2">
            <input
              type="number" min={320} max={7680} step={2}
              className="sm-input w-24"
              value={settings.targetWidth}
              onChange={(e) => update({ targetWidth: Number(e.target.value) })}
            />
            <span style={{ color: 'rgb(var(--surface-muted))' }}>×</span>
            <input
              type="number" min={240} max={4320} step={2}
              className="sm-input w-24"
              value={settings.targetHeight}
              onChange={(e) => update({ targetHeight: Number(e.target.value) })}
            />
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
              px — source aspect preserved via letterbox
            </span>
          </div>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Target framerate</label>
          <div className="flex items-center gap-2">
            <input
              type="number" min={15} max={120} step={1}
              className="sm-input w-20"
              value={settings.targetFps}
              onChange={(e) => update({ targetFps: Number(e.target.value) })}
            />
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>fps</span>
          </div>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Cross-dissolve</label>
          <div className="flex items-center gap-2">
            <input
              type="number" min={0.1} max={5.0} step={0.1}
              className="sm-input w-20"
              value={settings.xfadeDurationSecs}
              onChange={(e) => update({ xfadeDurationSecs: Number(e.target.value) })}
            />
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
              seconds between every clip + final fade-to-black
            </span>
          </div>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Title duration</label>
          <div className="flex items-center gap-2">
            <input
              type="number" min={2} max={60} step={1}
              className="sm-input w-20"
              value={settings.titleDurationSecs}
              onChange={(e) => update({ titleDurationSecs: Number(e.target.value) })}
            />
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
              seconds for the intro title card
            </span>
          </div>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Audio enhance</label>
          <label className="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={settings.audioEnhanceEnabled}
              onChange={(e) => update({ audioEnhanceEnabled: e.target.checked })}
            />
            <span className="text-xs">
              Apply <code>loudnorm -16 LUFS</code> + mild compressor + 200Hz/3kHz EQ to each clip
            </span>
          </label>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>DeepFilterNet</label>
          <div className="flex flex-col gap-1">
            <label
              className={`flex items-center gap-2 ${dfn?.installed ? 'cursor-pointer' : 'cursor-not-allowed opacity-60'}`}
              title={dfn?.installed ? '' : '`deep-filter` binary not found — install instructions below'}
            >
              <input
                type="checkbox"
                checked={settings.deepfilternetEnabled && (dfn?.installed ?? false)}
                disabled={!dfn?.installed}
                onChange={(e) => update({ deepfilternetEnabled: e.target.checked })}
              />
              <span className="text-xs">
                Voice isolation — DeepFilterNet pre-filter before the ffmpeg
                audio chain
              </span>
            </label>
            <DeepFilterStatus dfn={dfn} />
          </div>
        </div>

        <div className="flex justify-between items-center mt-1">
          <button type="button" className="sm-button secondary text-xs" onClick={resetDefaults}>
            Restore defaults
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

function DeepFilterStatus({ dfn }: { dfn: DeepFilterNetStatus | null }) {
  if (!dfn) return null;
  if (dfn.installed) {
    return (
      <div
        className="text-[11px] flex items-center gap-2 font-mono pl-6"
        style={{ color: '#0f5d33' }}
      >
        <span>✓ installed</span>
        {dfn.version && <span style={{ color: 'rgb(var(--surface-muted))' }}>· {dfn.version}</span>}
        {dfn.binPath && (
          <span
            className="truncate"
            style={{ color: 'rgb(var(--surface-muted))' }}
            title={dfn.binPath}
          >
            · {dfn.binPath}
          </span>
        )}
      </div>
    );
  }
  return (
    <div className="text-[11px] flex flex-col gap-0.5 pl-6">
      <span style={{ color: '#7a0000' }}>⚠ deep-filter binary not found</span>
      <span style={{ color: 'rgb(var(--surface-muted))' }}>
        Install (one-time, ~3 min):
      </span>
      <code
        className="text-[10px] p-1 rounded"
        style={{
          background: 'rgb(var(--surface-base))',
          border: '1px solid rgb(var(--surface-border))',
        }}
      >
        cargo install --git https://github.com/Rikorose/DeepFilterNet --bin deep-filter
      </code>
      <span style={{ color: 'rgb(var(--surface-muted))' }}>
        Or download a binary release from{' '}
        <a
          href="https://github.com/Rikorose/DeepFilterNet/releases"
          target="_blank"
          rel="noreferrer"
          style={{ color: 'rgb(var(--surface-accent))' }}
        >
          DeepFilterNet releases
        </a>
        {' '}and place it in <code>/opt/homebrew/bin</code> or{' '}
        <code>~/.cargo/bin</code>.
      </span>
    </div>
  );
}
