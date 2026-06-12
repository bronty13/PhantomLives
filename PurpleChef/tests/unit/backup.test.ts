import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, readdirSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let userDataDir: string;

vi.mock('electron', () => ({
  app: {
    getPath: (which: string): string => {
      if (which === 'userData') return userDataDir;
      throw new Error(`unexpected getPath(${which})`);
    },
    getName: () => 'Purple Chef',
    getVersion: () => '0.0.0-test'
  }
}));

import { listBackups, runBackup, trimRetention } from '../../src/main/backup';
import { resetStoreCaches, setPreferences } from '../../src/main/store';

let backupDir: string;

beforeEach(() => {
  userDataDir = mkdtempSync(join(tmpdir(), 'pchef-data-'));
  backupDir = join(mkdtempSync(join(tmpdir(), 'pchef-bk-')), 'nested', 'not-yet-created');
  writeFileSync(join(userDataDir, 'purple-chef-save.json'), '{"history":[]}');
  resetStoreCaches();
  setPreferences({ backupPath: backupDir, autoBackupEnabled: true, backupRetentionDays: 14, lastBackupMs: 0 });
});

afterEach(() => {
  rmSync(userDataDir, { recursive: true, force: true });
  rmSync(join(backupDir, '..', '..'), { recursive: true, force: true });
});

describe('backup service', () => {
  it('auto-creates the target directory and writes an archive', async () => {
    const r = await runBackup(true);
    expect(r.ok).toBe(true);
    expect(r.info?.name.startsWith('Purple Chef-')).toBe(true);
    expect(readdirSync(backupDir)).toHaveLength(1);
  });

  it('debounce: a second launch-run within 5 minutes is a no-op', async () => {
    const first = await runBackup(false);
    expect(first.ok).toBe(true);
    expect(first.skipped).toBeFalsy();
    const second = await runBackup(false);
    expect(second.skipped).toBe(true);
    expect(readdirSync(backupDir)).toHaveLength(1);
    // force ignores the debounce (wait out the 1-second filename resolution)
    await new Promise((res) => setTimeout(res, 1100));
    const forced = await runBackup(true);
    expect(forced.skipped).toBeFalsy();
    expect(readdirSync(backupDir)).toHaveLength(2);
  });

  it('respects autoBackupEnabled=false for launch runs', async () => {
    setPreferences({ autoBackupEnabled: false });
    const r = await runBackup(false);
    expect(r.skipped).toBe(true);
  });

  it('listBackups returns newest-first and only our archives', async () => {
    await runBackup(true);
    await new Promise((res) => setTimeout(res, 1100)); // distinct timestamp second
    await runBackup(true);
    writeFileSync(join(backupDir, 'unrelated.zip'), 'zz');
    const list = await listBackups();
    expect(list).toHaveLength(2);
    expect(list[0].createdMs).toBeGreaterThanOrEqual(list[1].createdMs);
    expect(list.every((b) => b.name.startsWith('Purple Chef-'))).toBe(true);
  });

  it('retention trims only our old archives; 0 keeps forever', async () => {
    mkdirSync(backupDir, { recursive: true });
    const oldOurs = join(backupDir, 'Purple Chef-2020-01-01-000000.zip');
    const oldTheirs = join(backupDir, 'vacation-photos.zip');
    writeFileSync(oldOurs, 'a');
    writeFileSync(oldTheirs, 'b');
    const past = new Date('2020-01-01').getTime() / 1000;
    utimesSync(oldOurs, past, past);
    utimesSync(oldTheirs, past, past);

    setPreferences({ backupRetentionDays: 0 });
    await trimRetention();
    expect(readdirSync(backupDir)).toContain('Purple Chef-2020-01-01-000000.zip');

    setPreferences({ backupRetentionDays: 14 });
    await trimRetention();
    const names = readdirSync(backupDir);
    expect(names).not.toContain('Purple Chef-2020-01-01-000000.zip');
    expect(names).toContain('vacation-photos.zip'); // unrelated files untouched
  });
});
