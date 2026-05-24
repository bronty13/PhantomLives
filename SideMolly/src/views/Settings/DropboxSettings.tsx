import { useEffect, useState } from 'react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { getDropboxSettings, setDropboxSettings,
         type DropboxSettings as DBS } from '../../data/bundles';

export function DropboxSettings() {
  const [settings, setSettings] = useState<DBS | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    getDropboxSettings()
      .then((s) => { if (alive) setSettings(s); })
      .catch((e) => setStatus(`Failed to load: ${e}`));
    return () => { alive = false; };
  }, []);

  if (!settings) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Loading…
      </div>
    );
  }

  const update = (patch: Partial<DBS>) => setSettings({ ...settings, ...patch });

  const browse = async () => {
    try {
      const picked = await openDialog({
        directory: true,
        multiple: false,
        title: 'Pick the local Dropbox folder',
      });
      if (typeof picked === 'string' && picked) {
        update({ rootPath: picked });
      }
    } catch (e) {
      setStatus(`Picker failed: ${e}`);
    }
  };

  const resetTemplate = () => update({ template: '[{date}] - {title}' });

  const save = async () => {
    setBusy(true);
    setStatus('');
    try {
      await setDropboxSettings(settings);
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
        <div className="font-semibold mb-1">Dropbox local-folder copy</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          Distributes processed bundle artifacts to your local Dropbox sync
          folder. The Dropbox app then syncs them up automatically — SideMolly
          never touches the Dropbox HTTP API. Each bundle gets a flat folder
          named per the template below.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-3">
        <div className="grid grid-cols-[160px_1fr] gap-x-3 gap-y-3 text-sm items-center">
          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Dropbox root</label>
          <div className="flex items-center gap-2">
            <input
              type="text"
              className="sm-input flex-1"
              value={settings.rootPath}
              placeholder="~/Dropbox/"
              onChange={(e) => update({ rootPath: e.target.value })}
            />
            <button type="button" className="sm-button secondary text-xs" onClick={browse}>
              📁 Browse…
            </button>
          </div>

          <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Folder template</label>
          <div className="flex items-center gap-2">
            <input
              type="text"
              className="sm-input flex-1 font-mono"
              value={settings.template}
              onChange={(e) => update({ template: e.target.value })}
            />
            <button type="button" className="sm-button secondary text-xs" onClick={resetTemplate}>
              Reset
            </button>
          </div>

          <div />
          <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
            Variables: <code>{'{date}'}</code> (YYYY-MM-DD, ingested),{' '}
            <code>{'{title}'}</code>, <code>{'{uid}'}</code>,{' '}
            <code>{'{persona}'}</code>. Default:{' '}
            <code>{'[{date}] - {title}'}</code>
          </div>
        </div>

        <div className="flex justify-end items-center gap-3">
          {status && (
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>{status}</span>
          )}
          <button type="button" className="sm-button" disabled={busy} onClick={save}>
            💾 Save
          </button>
        </div>
      </div>
    </div>
  );
}
