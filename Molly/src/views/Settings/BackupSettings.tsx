import { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { open as openDialog } from '@tauri-apps/plugin-dialog';

interface BackupSettingsDto {
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

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

export function BackupSettings() {
  const [settings, setSettings] = useState<BackupSettingsDto | null>(null);
  const [rows, setRows] = useState<BackupRow[]>([]);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const s = await invoke<BackupSettingsDto>('get_backup_settings');
    setSettings(s);
    const r = await invoke<BackupRow[]>('list_backups');
    setRows(r);
  }

  useEffect(() => {
    refresh().catch((e: unknown) => setStatus(`Couldn't load backup info: ${String(e)}`));
  }, []);

  if (!settings) return <div className="pretty-card">Loading backup settings…</div>;

  async function save(patch: Partial<BackupSettingsDto>) {
    if (!settings) return;
    const next = { ...settings, ...patch };
    setSettings(next);
    await invoke('set_backup_settings', { settings: next });
  }

  async function runNow() {
    setBusy(true);
    setStatus('Running backup…');
    try {
      const path: string = await invoke('run_backup_now');
      setStatus(`Backed up to ${path}`);
      await refresh();
    } catch (e) {
      setStatus(`Backup failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function pickPath() {
    if (!settings) return;
    const dir = await openDialog({
      directory: true,
      multiple: false,
      title: 'Pick a backup folder',
      defaultPath: settings.backupPath ?? undefined,
    });
    if (typeof dir === 'string') {
      await save({ backupPath: dir });
    }
  }

  async function revealDir() {
    try {
      await invoke('reveal_backup_dir');
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function reveal(path: string) {
    try {
      await invoke('reveal_path', { path });
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function testArchive(path: string) {
    setBusy(true);
    try {
      const v: VerifyResult = await invoke('test_backup', { path });
      const okBadge = v.hasDatabase ? '✅ database present' : '⚠️ no molly.db inside';
      setStatus(`${path.split('/').pop()}: ${okBadge}, ${v.fileCount} files, ${formatBytes(v.totalBytes)} unpacked`);
    } catch (e) {
      setStatus(`Verify failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function restoreArchive(path: string) {
    if (!confirm(`Restore from "${path.split('/').pop()}"?\n\nThis replaces all current Molly data. A safety pre-restore archive will be saved first.`)) return;
    setBusy(true);
    try {
      const safety: string = await invoke('restore_backup', { path });
      setStatus(`Restored. Safety archive at ${safety}. Please relaunch Molly.`);
      await refresh();
    } catch (e) {
      setStatus(`Restore failed: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  const resolvedPath = settings.backupPath?.trim() || '(default ~/Downloads/Molly backup/)';

  return (
    <div className="space-y-4">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">Backup</h3>
        <p className="text-sm opacity-70 mb-4">
          Molly zips its data folder on launch so a bad change can always be rolled back.
        </p>

        <div className="flex items-center gap-3 mb-4">
          <label className="flex items-center gap-2 text-sm font-medium">
            <input
              type="checkbox"
              checked={settings.autoBackupEnabled}
              onChange={(e) => save({ autoBackupEnabled: e.target.checked })}
            />
            Auto-backup on launch
          </label>
        </div>

        <div className="mb-3">
          <label className="block text-xs uppercase tracking-wider opacity-60 mb-1">Backup folder</label>
          <div className="flex gap-2">
            <input
              className="pretty-input flex-1"
              value={settings.backupPath ?? ''}
              placeholder="(default ~/Downloads/Molly backup/)"
              onChange={(e) => save({ backupPath: e.target.value || null })}
            />
            <button type="button" className="pretty-button secondary" onClick={pickPath}>Choose…</button>
            <button type="button" className="pretty-button secondary" onClick={() => save({ backupPath: null })}>Default</button>
          </div>
          <div className="mt-1 text-[11px] font-mono opacity-60">{resolvedPath}</div>
        </div>

        <div className="mb-4">
          <label className="block text-xs uppercase tracking-wider opacity-60 mb-1">Retention (days, 0 = forever)</label>
          <input
            type="number"
            min={0}
            max={365}
            className="pretty-input w-32"
            value={settings.backupRetentionDays}
            onChange={(e) => save({ backupRetentionDays: Math.max(0, Math.min(365, Number(e.target.value) || 0)) })}
          />
        </div>

        <div className="flex flex-wrap gap-2">
          <button type="button" className="pretty-button" onClick={runNow} disabled={busy}>
            ✨ Run Backup Now
          </button>
          <button type="button" className="pretty-button secondary" onClick={revealDir} disabled={busy}>
            🗂  Reveal in Finder
          </button>
        </div>

        <div className="mt-3 text-xs opacity-70">
          Last backup: {settings.lastBackupAt ?? 'never'}
        </div>
      </div>

      <div className="pretty-card">
        <h4 className="display-font text-lg font-semibold persona-accent mb-3">Recent backups</h4>
        {rows.length === 0 && <div className="text-sm opacity-60">No backups yet. Click <em>Run Backup Now</em>.</div>}
        <div className="space-y-2">
          {rows.map((r) => (
            <div key={r.path} className="flex items-center justify-between gap-3 p-2 rounded-xl border border-black/5">
              <div className="text-sm">
                <div className="font-mono">{r.filename}</div>
                <div className="opacity-60 text-xs">{r.modifiedAt} · {formatBytes(r.sizeBytes)}</div>
              </div>
              <div className="flex gap-2">
                <button className="pretty-button secondary" onClick={() => testArchive(r.path)} disabled={busy}>Test</button>
                <button className="pretty-button danger" onClick={() => restoreArchive(r.path)} disabled={busy}>Restore</button>
                <button className="pretty-button secondary" onClick={() => reveal(r.path)} disabled={busy}>Reveal</button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {status && (
        <div className="pretty-card text-sm">
          <strong>Status:</strong> {status}
        </div>
      )}
    </div>
  );
}
