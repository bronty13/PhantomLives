import { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';

interface Settings {
  autoBackupEnabled: boolean;
  backupPath: string | null;
  backupRetentionDays: number;
  lastBackupAt: string | null;
}

interface BackupRow {
  path: string;
  filename: string;
  modifiedAt: string;
  sizeBytes: number;
}

interface VerifyResult {
  archivePath: string;
  archiveSize: number;
  fileCount: number;
  totalBytes: number;
  hasDatabase: boolean;
  entries: string[];
}

// Satisfies the non-negotiable Settings → Backup UI per CLAUDE.md (toggle /
// path picker + Choose…/Default / retention stepper / Run Backup Now / Reveal
// / Recent list with Test+Restore+Reveal / last-backup readout / status line).
// Commands invoke the Rust side ported from SideMolly's backup.rs.
export function BackupSettings() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [backups, setBackups] = useState<BackupRow[]>([]);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [verify, setVerify] = useState<VerifyResult | null>(null);

  const refresh = async () => {
    try {
      const [s, list] = await Promise.all([
        invoke<Settings>('get_backup_settings'),
        invoke<BackupRow[]>('list_backups'),
      ]);
      setSettings(s);
      setBackups(list);
    } catch (e) {
      setStatus(`Failed to load settings: ${e}`);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const save = async (patch: Partial<Settings>) => {
    if (!settings) return;
    const next = { ...settings, ...patch };
    setSettings(next);
    try {
      await invoke('set_backup_settings', { settings: next });
      setStatus('Settings saved.');
    } catch (e) {
      setStatus(`Save failed: ${e}`);
    }
  };

  const chooseDir = async () => {
    const picked = await open({ directory: true, multiple: false });
    if (picked && typeof picked === 'string') await save({ backupPath: picked });
  };

  const runNow = async () => {
    setBusy(true);
    setStatus('Running backup…');
    try {
      const out = await invoke<string>('run_backup_now');
      setStatus(`Backup written to ${out}`);
      await refresh();
    } catch (e) {
      setStatus(`Backup failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const test = async (path: string) => {
    setBusy(true);
    setStatus('Verifying archive…');
    try {
      const v = await invoke<VerifyResult>('test_backup', { path });
      setVerify(v);
      setStatus(
        `Verified ${v.fileCount} files (${(v.archiveSize / 1024).toFixed(1)} KB).` +
          (v.hasDatabase ? '' : ' ⚠ No purplemind.db inside.'),
      );
    } catch (e) {
      setStatus(`Verify failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const restore = async (path: string) => {
    if (
      !confirm(
        'Replace live app data with this backup? A safety pre-restore archive will be written first.',
      )
    )
      return;
    setBusy(true);
    setStatus('Restoring…');
    try {
      const safety = await invoke<string>('restore_backup', { path });
      setStatus(`Restored. Safety archive: ${safety}. Restart PurpleMind to load it.`);
      await refresh();
    } catch (e) {
      setStatus(`Restore failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const reveal = async (path: string) => {
    try {
      await invoke('reveal_path', { path });
    } catch (e) {
      setStatus(`Reveal failed: ${e}`);
    }
  };

  const revealBackupDir = async () => {
    try {
      await invoke('reveal_backup_dir');
    } catch (e) {
      setStatus(`Reveal failed: ${e}`);
    }
  };

  if (!settings) return <div className="card p-4">Loading…</div>;

  return (
    <div className="flex flex-col gap-4">
      <div className="card p-4">
        <label className="flex cursor-pointer items-center gap-3">
          <input
            type="checkbox"
            checked={settings.autoBackupEnabled}
            onChange={(e) => save({ autoBackupEnabled: e.target.checked })}
          />
          <span className="font-semibold">Run a backup on every launch</span>
        </label>
        <div className="mt-1 text-xs text-surface-muted">
          Skipped if the previous backup is under 5 minutes old. Failures log to
          stderr and never block launch.
        </div>
      </div>

      <div className="card p-4">
        <div className="mb-2 font-semibold">Backup location</div>
        <div className="flex items-center gap-2">
          <input
            type="text"
            className="field flex-1 font-mono text-xs"
            value={settings.backupPath ?? ''}
            placeholder="(default — ~/Downloads/PurpleMind backup/)"
            onChange={(e) => save({ backupPath: e.target.value || null })}
          />
          <button type="button" className="btn-soft" onClick={chooseDir}>
            Choose…
          </button>
          <button type="button" className="btn-soft" onClick={() => save({ backupPath: null })}>
            Default
          </button>
          <button type="button" className="btn-soft" onClick={revealBackupDir}>
            📁 Reveal
          </button>
        </div>
      </div>

      <div className="card p-4">
        <div className="mb-2 font-semibold">Retention</div>
        <div className="flex items-center gap-3">
          <input
            type="number"
            min={0}
            max={365}
            className="field w-24"
            value={settings.backupRetentionDays}
            onChange={(e) =>
              save({
                backupRetentionDays: Math.max(0, Math.min(365, Number(e.target.value) || 0)),
              })
            }
          />
          <span className="text-sm text-surface-muted">days · 0 = keep forever</span>
        </div>
      </div>

      <div className="card p-4">
        <div className="mb-2 flex items-center justify-between">
          <div className="font-semibold">Recent backups ({backups.length})</div>
          <button type="button" className="btn-primary" onClick={runNow} disabled={busy}>
            {busy ? '⏳ Working…' : '▶ Run Backup Now'}
          </button>
        </div>
        <div className="mb-3 text-xs text-surface-muted">
          Last backup: {settings.lastBackupAt ?? '(never)'}
        </div>

        {backups.length === 0 ? (
          <div className="text-sm text-surface-muted">
            No backups yet. Run one now to populate the list.
          </div>
        ) : (
          <ul className="flex flex-col gap-2">
            {backups.map((b) => (
              <li
                key={b.path}
                className="flex items-center gap-2 border-t border-surface-border pt-2 text-sm"
              >
                <div className="min-w-0 flex-1">
                  <div className="truncate font-mono">{b.filename}</div>
                  <div className="text-xs text-surface-muted">
                    {b.modifiedAt} · {(b.sizeBytes / 1024).toFixed(1)} KB
                  </div>
                </div>
                <button type="button" className="btn-soft" onClick={() => test(b.path)} disabled={busy}>
                  Test
                </button>
                <button
                  type="button"
                  className="btn bg-red-500 text-white hover:bg-red-600"
                  onClick={() => restore(b.path)}
                  disabled={busy}
                >
                  Restore
                </button>
                <button type="button" className="btn-soft" onClick={() => reveal(b.path)}>
                  Reveal
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {verify && (
        <div className="card p-4">
          <div className="mb-2 font-semibold">Last verification</div>
          <div className="font-mono text-xs">{verify.archivePath}</div>
          <div className="mt-1 text-sm">
            {verify.fileCount} files · {(verify.totalBytes / 1024).toFixed(1)} KB total ·{' '}
            {verify.hasDatabase ? '✓ database present' : '⚠ no purplemind.db'}
          </div>
        </div>
      )}

      {status && <div className="text-sm text-surface-muted">{status}</div>}
    </div>
  );
}
