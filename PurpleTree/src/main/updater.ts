// Auto-update wrapper around electron-updater.
//
// Graceful no-op when running in dev, when no publish provider is configured,
// or when the update server returns 404 / network error. We never crash the
// app over update failures — this is best-effort.

import { app, dialog, type BrowserWindow } from 'electron';
import { autoUpdater } from 'electron-updater';

let lastInteractiveCheck = 0;

export interface UpdateCheckResult {
  ok: boolean;
  available: boolean;
  version?: string;
  reason?: string;
}

function configure(): void {
  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = true;
}

export function scheduleStartupCheck(getWin: () => BrowserWindow | null): void {
  if (!app.isPackaged) return;
  configure();
  setTimeout(() => {
    void checkForUpdates(getWin(), false);
  }, 5000);
}

export async function checkForUpdates(
  win: BrowserWindow | null,
  interactive: boolean
): Promise<UpdateCheckResult> {
  if (!app.isPackaged) {
    if (interactive && win) {
      await dialog.showMessageBox(win, {
        type: 'info',
        message: 'Updates unavailable in development',
        detail: 'Auto-update only runs in packaged builds. Run `npm run dist` to test.',
        buttons: ['OK']
      });
    }
    return { ok: false, available: false, reason: 'dev-mode' };
  }
  const now = Date.now();
  if (interactive) {
    if (now - lastInteractiveCheck < 30_000) {
      return { ok: false, available: false, reason: 'throttled' };
    }
    lastInteractiveCheck = now;
  }

  configure();
  try {
    const result = await autoUpdater.checkForUpdates();
    if (!result) {
      if (interactive && win) {
        await dialog.showMessageBox(win, {
          type: 'info',
          message: "You're up to date",
          detail: `Purple Tree ${app.getVersion()} is the latest version.`,
          buttons: ['OK']
        });
      }
      return { ok: true, available: false };
    }
    const remoteVersion = result.updateInfo.version;
    const isNewer = remoteVersion !== app.getVersion();
    if (!isNewer) {
      if (interactive && win) {
        await dialog.showMessageBox(win, {
          type: 'info',
          message: "You're up to date",
          detail: `Purple Tree ${app.getVersion()} is the latest version.`,
          buttons: ['OK']
        });
      }
      return { ok: true, available: false, version: remoteVersion };
    }
    if (!win) return { ok: true, available: true, version: remoteVersion };
    const choice = await dialog.showMessageBox(win, {
      type: 'info',
      message: `Purple Tree ${remoteVersion} is available`,
      detail: `You're running ${app.getVersion()}. Download and install on next quit?`,
      buttons: ['Download', 'Later'],
      defaultId: 0,
      cancelId: 1
    });
    if (choice.response === 0) {
      try {
        await autoUpdater.downloadUpdate();
        await dialog.showMessageBox(win, {
          type: 'info',
          message: 'Update downloaded',
          detail: 'The update will install automatically when you quit Purple Tree.',
          buttons: ['OK']
        });
      } catch (e) {
        await dialog.showMessageBox(win, {
          type: 'error',
          message: 'Update download failed',
          detail: e instanceof Error ? e.message : String(e),
          buttons: ['OK']
        });
      }
    }
    return { ok: true, available: true, version: remoteVersion };
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    if (interactive && win) {
      await dialog.showMessageBox(win, {
        type: 'warning',
        message: 'Could not check for updates',
        detail: reason + '\n\nThis is normal if no release feed is configured yet.',
        buttons: ['OK']
      });
    }
    return { ok: false, available: false, reason };
  }
}
