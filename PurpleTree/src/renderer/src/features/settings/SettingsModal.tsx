import { useEffect, useState } from 'react';
import type { BackupInfo } from '../../../../shared/types';
import { formatBytes, formatDate } from '../common/format';

const api = window.purpleTree;

interface Prefs {
  scanOptions: { followSymlinks: boolean; crossMountPoints: boolean; dedupHardLinks: boolean };
  permanentDeleteEnabled: boolean;
  exportDir: string;
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  lastBackupMs: number;
}

interface Props {
  onClose: () => void;
  onPrefsChanged: () => void;
}

export default function SettingsModal({ onClose, onPrefsChanged }: Props): JSX.Element {
  const [tab, setTab] = useState<'general' | 'backup'>('general');
  const [prefs, setPrefs] = useState<Prefs | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [status, setStatus] = useState('');

  const loadPrefs = (): void => {
    void api.prefsGet().then((p) => setPrefs(p as unknown as Prefs));
  };
  const loadBackups = (): void => {
    void api.backupList().then(setBackups);
  };
  useEffect(() => {
    loadPrefs();
    loadBackups();
  }, []);

  const patch = async (p: Partial<Prefs>): Promise<void> => {
    const next = (await api.prefsSet(p as never)) as unknown as Prefs;
    setPrefs(next);
    onPrefsChanged();
  };

  if (!prefs) return <div className="modal-backdrop" />;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal settings" onClick={(e) => e.stopPropagation()}>
        <div className="settings-tabs">
          <button className={tab === 'general' ? 'active' : ''} onClick={() => setTab('general')}>
            General
          </button>
          <button className={tab === 'backup' ? 'active' : ''} onClick={() => setTab('backup')}>
            Backup
          </button>
          <div className="spacer" />
          <button onClick={onClose}>Close</button>
        </div>

        {tab === 'general' && (
          <div className="settings-body">
            <h3>Scanning</h3>
            <label className="row-check">
              <input
                type="checkbox"
                checked={prefs.scanOptions.dedupHardLinks}
                onChange={(e) =>
                  void patch({ scanOptions: { ...prefs.scanOptions, dedupHardLinks: e.target.checked } })
                }
              />
              De-duplicate hard links in folder totals (macOS/Linux only)
            </label>
            <label className="row-check">
              <input
                type="checkbox"
                checked={prefs.scanOptions.crossMountPoints}
                onChange={(e) =>
                  void patch({ scanOptions: { ...prefs.scanOptions, crossMountPoints: e.target.checked } })
                }
              />
              Cross mount points / other volumes while scanning
            </label>
            <label className="row-check">
              <input
                type="checkbox"
                checked={prefs.scanOptions.followSymlinks}
                onChange={(e) =>
                  void patch({ scanOptions: { ...prefs.scanOptions, followSymlinks: e.target.checked } })
                }
              />
              Follow symbolic links (off is safer — avoids loops)
            </label>

            <h3>Deletion</h3>
            <label className="row-check">
              <input
                type="checkbox"
                checked={prefs.permanentDeleteEnabled}
                onChange={(e) => void patch({ permanentDeleteEnabled: e.target.checked })}
              />
              Enable permanent delete (otherwise everything goes to the Trash)
            </label>

            <h3>Exports</h3>
            <div className="path-caption">Reports are saved to: {prefs.exportDir}</div>
          </div>
        )}

        {tab === 'backup' && (
          <div className="settings-body">
            <label className="row-check">
              <input
                type="checkbox"
                checked={prefs.autoBackupEnabled}
                onChange={(e) => void patch({ autoBackupEnabled: e.target.checked })}
              />
              Automatically back up my settings &amp; snapshots on launch
            </label>

            <h3>Backup folder</h3>
            <div className="backup-dir-row">
              <button
                onClick={async () => {
                  const dir = await api.backupPickDir();
                  if (dir) void patch({ backupPath: dir });
                }}
              >
                Choose…
              </button>
              <button onClick={() => void api.backupReveal()}>Reveal in Finder</button>
            </div>
            <div className="path-caption">{prefs.backupPath}</div>

            <h3>Retention</h3>
            <label className="row-inline">
              Keep backups for{' '}
              <input
                type="number"
                min={0}
                max={365}
                value={prefs.backupRetentionDays}
                onChange={(e) => void patch({ backupRetentionDays: Number(e.target.value) })}
              />{' '}
              days (0 = keep forever)
            </label>

            <div className="backup-actions">
              <button
                className="btn-primary"
                onClick={async () => {
                  setStatus('Backing up…');
                  const r = await api.backupRun();
                  setStatus(r.ok ? (r.skipped ? 'Skipped (recent backup exists).' : 'Backup complete.') : `Failed: ${r.error}`);
                  loadBackups();
                  loadPrefs();
                }}
              >
                Run Backup Now
              </button>
              <span className="muted">
                Last backup: {prefs.lastBackupMs ? formatDate(prefs.lastBackupMs) : 'never'}
              </span>
            </div>
            {status && <div className="status-line">{status}</div>}

            <h3>Recent backups</h3>
            <div className="backup-list">
              {backups.length === 0 && <p className="muted">No backups yet.</p>}
              {backups.map((b) => (
                <div key={b.path} className="backup-row">
                  <span className="backup-name" title={b.path}>
                    {b.name}
                  </span>
                  <span className="muted">{formatBytes(b.sizeBytes)}</span>
                  <button
                    onClick={async () => {
                      const r = await api.backupTest(b.path);
                      setStatus(
                        r.ok
                          ? `✓ Valid — ${r.fileCount} files${r.hasPrefs ? ', settings present' : ''}.`
                          : `✗ Invalid: ${r.error}`
                      );
                    }}
                  >
                    Test
                  </button>
                  <button
                    className="btn-danger"
                    onClick={async () => {
                      if (
                        !window.confirm(
                          'Restore this backup? Your current settings & snapshots will be replaced (a pre-restore safety backup is taken first).'
                        )
                      )
                        return;
                      setStatus('Restoring…');
                      const r = await api.backupRestore(b.path);
                      setStatus(r.ok ? 'Restored. Restart Purple Tree to load it.' : `Failed: ${r.error}`);
                      loadBackups();
                    }}
                  >
                    Restore
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
