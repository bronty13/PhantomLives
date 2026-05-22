import { invoke } from '@tauri-apps/api/core';

// Auto-managed ATW bot install. Molly ships repost.js + package.json
// as bundled resources and copies them into app_data/atw-bot/ on
// first use, then runs `npm install` there. Sallie never picks a
// directory in the zero-config flow.

export interface SetupState {
  botDir: string;
  filesCopied: boolean;
  installedVersion: string | null;
  bundledVersion: string | null;
  needsNpmInstall: boolean;
  nodeModulesPresent: boolean;
}

export interface InstallResult {
  status: 'success' | 'failed';
  summary: string;
  logExcerpt: string;
  elapsedSeconds: number;
}

export async function inspectAtwSetup(): Promise<SetupState> {
  return invoke<SetupState>('inspect_atw_setup');
}

export async function ensureAtwBotFiles(): Promise<SetupState> {
  return invoke<SetupState>('ensure_atw_bot_files');
}

export async function installAtwBotDeps(): Promise<InstallResult> {
  return invoke<InstallResult>('install_atw_bot_deps');
}
