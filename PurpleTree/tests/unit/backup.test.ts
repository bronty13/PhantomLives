import { describe, it, expect, beforeEach, vi } from 'vitest';
import { existsSync, mkdirSync, rmSync, readdirSync, utimesSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Hoisted shared state so the electron + prefs mocks can reference temp dirs.
const h = vi.hoisted(() => {
  /* eslint-disable @typescript-eslint/no-var-requires */
  const os = require('node:os');
  const fs = require('node:fs');
  const path = require('node:path');
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'pt-backup-'));
  const dataDir = path.join(base, 'data');
  const backupDir = path.join(base, 'backups');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'purple-tree-prefs.json'), '{"version":1}');
  const prefs = {
    autoBackupEnabled: true,
    backupPath: backupDir,
    backupRetentionDays: 14,
    lastBackupMs: 0
  };
  return { base, dataDir, backupDir, prefs };
});

vi.mock('electron', () => ({
  app: { getName: () => 'Purple Tree', getPath: () => h.dataDir }
}));
vi.mock('../../src/main/prefs', () => ({
  getPreferences: () => h.prefs,
  setPreferences: (patch: Record<string, unknown>) => {
    Object.assign(h.prefs, patch);
    return h.prefs;
  }
}));

import { runBackup, listBackups, trimRetention } from '../../src/main/backup/backupService';

beforeEach(() => {
  rmSync(h.backupDir, { recursive: true, force: true });
  mkdirSync(h.backupDir, { recursive: true });
  h.prefs.lastBackupMs = 0;
  h.prefs.backupRetentionDays = 14;
  h.prefs.autoBackupEnabled = true;
});

describe('BackupService', () => {
  it('creates a backup zip and auto-creates the destination dir', async () => {
    rmSync(h.backupDir, { recursive: true, force: true }); // dir absent
    const r = await runBackup(true);
    expect(r.ok).toBe(true);
    expect(r.info?.name).toMatch(/^Purple Tree-/);
    expect(existsSync(r.info!.path)).toBe(true);
    expect(existsSync(h.backupDir)).toBe(true);
  });

  it('debounces a non-forced run within 5 minutes', async () => {
    h.prefs.lastBackupMs = Date.now();
    const r = await runBackup(false);
    expect(r.skipped).toBe(true);
    expect(readdirSync(h.backupDir)).toHaveLength(0);
  });

  it('lists backups newest-first', async () => {
    const a = join(h.backupDir, 'Purple Tree-2026-01-01-000000.zip');
    const b = join(h.backupDir, 'Purple Tree-2026-06-01-000000.zip');
    writeFileSync(a, 'x');
    writeFileSync(b, 'x');
    const old = new Date('2026-01-01').getTime() / 1000;
    const recent = new Date('2026-06-01').getTime() / 1000;
    utimesSync(a, old, old);
    utimesSync(b, recent, recent);
    const list = await listBackups();
    expect(list[0].name).toContain('2026-06-01');
    expect(list[1].name).toContain('2026-01-01');
  });

  it('only trims our-prefixed files older than the retention window', async () => {
    const ours = join(h.backupDir, 'Purple Tree-2020-01-01-000000.zip');
    const unrelated = join(h.backupDir, 'someone-elses.zip');
    writeFileSync(ours, 'x');
    writeFileSync(unrelated, 'x');
    const ancient = new Date('2020-01-01').getTime() / 1000;
    utimesSync(ours, ancient, ancient);
    utimesSync(unrelated, ancient, ancient);
    h.prefs.backupRetentionDays = 14;
    await trimRetention();
    expect(existsSync(ours)).toBe(false); // ours, old -> trimmed
    expect(existsSync(unrelated)).toBe(true); // not our prefix -> left alone
  });

  it('keeps everything when retention is 0 (forever)', async () => {
    const ours = join(h.backupDir, 'Purple Tree-2020-01-01-000000.zip');
    writeFileSync(ours, 'x');
    const ancient = new Date('2020-01-01').getTime() / 1000;
    utimesSync(ours, ancient, ancient);
    h.prefs.backupRetentionDays = 0;
    await trimRetention();
    expect(existsSync(ours)).toBe(true);
  });
});
