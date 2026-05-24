import { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

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

// Phase 0 — satisfies the non-negotiable Settings → Backup UI per
// CLAUDE.md (toggle / retention stepper / Run Backup Now / Reveal /
// Recent list with Test+Restore+Reveal / last-backup readout / status
// line). All commands invoke the Rust side ported from Molly's backup.rs.
export function BackupSettings() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [backups, setBackups] = useState<BackupRow[]>([]);
  const [status, setStatus] = useState<string>('');
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
    refresh();
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
        (v.hasDatabase ? '' : ' ⚠ No sidemolly.db inside.'),
      );
    } catch (e) {
      setStatus(`Verify failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const restore = async (path: string) => {
    if (!confirm('Replace live app data with this backup? A safety pre-restore archive will be written first.')) return;
    setBusy(true);
    setStatus('Restoring…');
    try {
      const safety = await invoke<string>('restore_backup', { path });
      setStatus(`Restored. Safety archive: ${safety}`);
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

  if (!settings) return <div className="sm-card">Loading…</div>;

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={settings.autoBackupEnabled}
            onChange={(e) => save({ autoBackupEnabled: e.target.checked })}
          />
          <span className="font-semibold">Run a backup on every launch</span>
        </label>
        <div className="text-xs mt-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          Skipped if the previous backup is under 5 minutes old. Failures log to stderr and never crash launch.
        </div>
      </div>

      <div className="sm-card">
        <div className="font-semibold mb-2">Backup location</div>
        <div className="flex gap-2 items-center">
          <input
            type="text"
            className="sm-input flex-1"
            value={settings.backupPath ?? ''}
            placeholder="(default — ~/Downloads/SideMolly backup/)"
            onChange={(e) => save({ backupPath: e.target.value || null })}
          />
          <button type="button" className="sm-button secondary" onClick={() => save({ backupPath: null })}>
            Default
          </button>
          <button type="button" className="sm-button secondary" onClick={revealBackupDir}>
            📁 Reveal
          </button>
        </div>
      </div>

      <div className="sm-card">
        <div className="font-semibold mb-2">Retention</div>
        <div className="flex items-center gap-3">
          <input
            type="number"
            min={0}
            max={365}
            className="sm-input w-24"
            value={settings.backupRetentionDays}
            onChange={(e) =>
              save({ backupRetentionDays: Math.max(0, Math.min(365, Number(e.target.value) || 0)) })
            }
          />
          <span className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
            days · 0 = keep forever
          </span>
        </div>
      </div>

      <div className="sm-card">
        <div className="flex items-center justify-between mb-2">
          <div className="font-semibold">Recent backups ({backups.length})</div>
          <button type="button" className="sm-button" onClick={runNow} disabled={busy}>
            {busy ? '⏳ Working…' : '▶ Run Backup Now'}
          </button>
        </div>
        <div className="text-xs mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
          Last backup: {settings.lastBackupAt ?? '(never)'}
        </div>

        {backups.length === 0 ? (
          <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
            No backups yet. Run one now to populate the list.
          </div>
        ) : (
          <ul className="flex flex-col gap-2">
            {backups.map((b) => (
              <li
                key={b.path}
                className="flex items-center gap-2 text-sm"
                style={{ borderTop: '1px solid rgb(var(--surface-border))', paddingTop: 8 }}
              >
                <div className="flex-1 min-w-0">
                  <div className="font-mono truncate">{b.filename}</div>
                  <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
                    {b.modifiedAt} · {(b.sizeBytes / 1024).toFixed(1)} KB
                  </div>
                </div>
                <button type="button" className="sm-button secondary" onClick={() => test(b.path)} disabled={busy}>
                  Test
                </button>
                <button type="button" className="sm-button danger" onClick={() => restore(b.path)} disabled={busy}>
                  Restore
                </button>
                <button type="button" className="sm-button secondary" onClick={() => reveal(b.path)}>
                  Reveal
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {verify && (
        <div className="sm-card">
          <div className="font-semibold mb-2">Last verification</div>
          <div className="font-mono text-xs">{verify.archivePath}</div>
          <div className="text-sm mt-1">
            {verify.fileCount} files · {(verify.totalBytes / 1024).toFixed(1)} KB total ·{' '}
            {verify.hasDatabase ? '✓ database present' : '⚠ no sidemolly.db'}
          </div>
        </div>
      )}

      {status && (
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          {status}
        </div>
      )}
    </div>
  );
}
