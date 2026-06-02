import { useEffect, useState } from 'react';
import { getEditDefaults, setEditDefaults,
         type EditDefaults as ED } from '../../data/bundles';

const DEFAULTS: ED = {
  imageWatermark: true, imageStripExif: true, imageRename: true,
  videoWatermark: true, videoStripMetadata: true, videoRename: true,
};

export function EditDefaultsSettings() {
  const [settings, setSettings] = useState<ED | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    getEditDefaults()
      .then((s) => { if (alive) setSettings(s); })
      .catch((e) => setStatus(`Failed to load: ${e}`));
    return () => { alive = false; };
  }, []);

  if (!settings) {
    return <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>;
  }

  const update = (patch: Partial<ED>) => setSettings({ ...settings, ...patch });

  const save = async () => {
    setBusy(true);
    setStatus('');
    try {
      await setEditDefaults(settings);
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
        <div className="font-semibold mb-1">Edit defaults</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          The toggle states the <strong>Edit tab</strong> starts with when you
          open a bundle. These are global — they apply to every persona. You can
          still flip any toggle per-bundle before processing; this just sets the
          starting point.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-4">
        <OpsGroup
          title="🖼 Image ops"
          rows={[
            { label: '🖋 Watermark', checked: settings.imageWatermark, set: (v) => update({ imageWatermark: v }) },
            { label: '🪪 Strip EXIF', checked: settings.imageStripExif, set: (v) => update({ imageStripExif: v }) },
            { label: '🏷 Rename', checked: settings.imageRename, set: (v) => update({ imageRename: v }) },
          ]}
        />
        <OpsGroup
          title="🎥 Video ops"
          rows={[
            { label: '🖋 Watermark', checked: settings.videoWatermark, set: (v) => update({ videoWatermark: v }) },
            { label: '🪪 Strip metadata', checked: settings.videoStripMetadata, set: (v) => update({ videoStripMetadata: v }) },
            { label: '🏷 Rename', checked: settings.videoRename, set: (v) => update({ videoRename: v }) },
          ]}
        />

        <div className="flex justify-between items-center mt-1">
          <button type="button" className="sm-button secondary text-xs"
                  onClick={() => setSettings(DEFAULTS)}>
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

function OpsGroup({ title, rows }: {
  title: string;
  rows: { label: string; checked: boolean; set: (v: boolean) => void }[];
}) {
  return (
    <div>
      <div className="text-xs font-semibold mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>{title}</div>
      <div className="flex flex-col gap-2">
        {rows.map((r) => (
          <label key={r.label} className="flex items-center gap-2 cursor-pointer text-sm">
            <input type="checkbox" checked={r.checked} onChange={(e) => r.set(e.target.checked)} />
            <span>{r.label}</span>
          </label>
        ))}
      </div>
    </div>
  );
}
