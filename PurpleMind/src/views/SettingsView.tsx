import { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { BackupSettings } from './BackupSettings';
import { getExportDir, setExportDir } from '../data/appSettings';

export function SettingsView() {
  const [exportDir, setDir] = useState('');
  const [resolved, setResolved] = useState('');

  const refreshResolved = async (override: string) => {
    const r = await invoke<string>('export_dir', { dirOverride: override || null });
    setResolved(r);
  };

  useEffect(() => {
    void (async () => {
      const d = await getExportDir();
      setDir(d);
      await refreshResolved(d);
    })();
  }, []);

  const persist = async (value: string) => {
    setDir(value);
    await setExportDir(value);
    await refreshResolved(value);
  };

  const chooseExportDir = async () => {
    const picked = await open({ directory: true, multiple: false });
    if (picked && typeof picked === 'string') await persist(picked);
  };

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-2xl px-6 py-6">
        <h1 className="mb-4 font-display text-2xl text-brand-600">Settings</h1>

        <section className="mb-6">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-surface-muted">
            Export location
          </h2>
          <div className="card p-4">
            <div className="flex items-center gap-2">
              <input
                type="text"
                className="field flex-1 font-mono text-xs"
                value={exportDir}
                placeholder="(default — ~/Downloads/PurpleMind/)"
                onChange={(e) => persist(e.target.value)}
              />
              <button type="button" className="btn-soft" onClick={chooseExportDir}>
                Choose…
              </button>
              <button type="button" className="btn-soft" onClick={() => persist('')}>
                Default
              </button>
            </div>
            <div className="mt-2 font-mono text-xs text-surface-muted">
              Exports save to: {resolved}
            </div>
          </div>
        </section>

        <section>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-surface-muted">
            Backup
          </h2>
          <BackupSettings />
        </section>
      </div>
    </div>
  );
}
