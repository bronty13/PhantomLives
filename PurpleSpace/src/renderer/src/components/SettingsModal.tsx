import React, { useCallback, useEffect, useState } from 'react';
import type { ThemeSetting, BackupInfo, Preferences } from '../../../shared/types';

interface SettingsModalProps {
  theme: ThemeSetting;
  onTheme: (t: ThemeSetting) => void;
  onClose: () => void;
  showToast: (msg: string) => void;
}

export default function SettingsModal({ theme, onTheme, onClose, showToast }: SettingsModalProps): React.JSX.Element {
  const [prefs, setPrefs] = useState<Preferences | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (): Promise<void> => {
    setPrefs(await window.purpleSpace.prefsGet());
    setBackups(await window.purpleSpace.backupList());
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const patch = async (p: Partial<Preferences>): Promise<void> => {
    setPrefs(await window.purpleSpace.prefsSet(p));
  };

  const runNow = async (): Promise<void> => {
    setBusy(true);
    const res = await window.purpleSpace.backupRun();
    setBusy(false);
    showToast(res.ok ? `Backup written: ${res.info?.name}` : `Backup failed: ${res.error}`);
    void refresh();
  };

  const testLatest = async (): Promise<void> => {
    if (!backups[0]) return;
    const res = await window.purpleSpace.backupTest(backups[0].path);
    showToast(
      res.ok
        ? `OK — ${res.fileCount} files${res.hasPrefs ? ', prefs present' : ''}`
        : `Archive failed verification: ${res.error ?? 'no files'}`
    );
  };

  const restore = async (): Promise<void> => {
    const zip = await window.purpleSpace.backupPickZip();
    if (!zip) return;
    if (
      !window.confirm(
        'Restore this backup? Current data is backed up first, then the app restarts with the restored workspace.'
      )
    ) {
      return;
    }
    setBusy(true);
    const res = await window.purpleSpace.backupRestore(zip);
    setBusy(false);
    if (!res.ok) showToast(`Restore failed: ${res.error}`);
    // on success the app relaunches itself
  };

  const fmtSize = (n: number): string =>
    n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`;

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="settings" onMouseDown={(e) => e.stopPropagation()}>
        <div className="settings-head">
          <h2>Settings</h2>
          <button className="btn" onClick={onClose}>
            Done
          </button>
        </div>
        <div className="settings-body scrolly">
          <div className="settings-section">
            <h3>Appearance</h3>
            <div className="settings-row">
              <div>
                Theme
                <div className="desc">⌘⇧L toggles light/dark anytime.</div>
              </div>
              <div className="seg">
                {(['system', 'light', 'dark'] as ThemeSetting[]).map((t) => (
                  <button key={t} className={theme === t ? 'on' : ''} onClick={() => onTheme(t)}>
                    {t[0].toUpperCase() + t.slice(1)}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="settings-section">
            <h3>Export</h3>
            <div className="settings-row">
              <div>
                Markdown exports land in
                <div className="desc">{prefs?.exportDir ?? '…'}</div>
              </div>
            </div>
          </div>

          <div className="settings-section">
            <h3>Backup</h3>
            <div className="settings-row">
              <div>
                Back up automatically on launch
                <div className="desc">Zips the whole workspace (pages, files, settings).</div>
              </div>
              <input
                type="checkbox"
                className="db-checkbox"
                checked={prefs?.autoBackupEnabled ?? true}
                onChange={(e) => void patch({ autoBackupEnabled: e.target.checked })}
              />
            </div>
            <div className="settings-row">
              <div>
                Backup folder
                <div className="desc">{prefs?.backupPath ?? '…'}</div>
              </div>
              <div style={{ display: 'flex', gap: 6 }}>
                <button
                  className="btn"
                  onClick={() =>
                    void window.purpleSpace.backupPickDir().then((dir) => {
                      if (dir) void patch({ backupPath: dir }).then(refresh);
                    })
                  }
                >
                  Change…
                </button>
                <button className="btn" onClick={() => void window.purpleSpace.backupReveal()}>
                  Reveal
                </button>
              </div>
            </div>
            <div className="settings-row">
              <div>
                Keep backups for
                <div className="desc">Older archives are deleted after a successful backup. 0 = keep forever.</div>
              </div>
              <div className="seg">
                {[7, 14, 30, 0].map((d) => (
                  <button
                    key={d}
                    className={prefs?.backupRetentionDays === d ? 'on' : ''}
                    onClick={() => void patch({ backupRetentionDays: d })}
                  >
                    {d === 0 ? 'Forever' : `${d} days`}
                  </button>
                ))}
              </div>
            </div>
            <div className="settings-row" style={{ borderBottom: 'none' }}>
              <div style={{ display: 'flex', gap: 8 }}>
                <button className="btn primary" disabled={busy} onClick={() => void runNow()}>
                  Back Up Now
                </button>
                <button className="btn" disabled={busy || !backups.length} onClick={() => void testLatest()}>
                  Test Latest
                </button>
                <button className="btn danger" disabled={busy} onClick={() => void restore()}>
                  Restore…
                </button>
              </div>
            </div>
            <ul className="backup-list">
              {backups.slice(0, 8).map((b) => (
                <li key={b.path}>
                  <span className="grow">{b.name}</span>
                  <span>{fmtSize(b.sizeBytes)}</span>
                  <button
                    className="mini-btn"
                    onClick={() =>
                      void window.purpleSpace.backupTest(b.path).then((r) =>
                        showToast(r.ok ? `OK — ${r.fileCount} files` : `Failed: ${r.error ?? 'no files'}`)
                      )
                    }
                  >
                    Test
                  </button>
                </li>
              ))}
              {!backups.length && <li>No backups yet.</li>}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
