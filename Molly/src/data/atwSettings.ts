import { invoke } from '@tauri-apps/api/core';

// ATW Repost bot settings + health check.
//
// The password is stored encrypted in app-data/atw-settings.json
// (wrapped against the keystore DEK from PR1). The frontend never
// holds the wrapped DEK; setting a password sends plaintext → Rust
// encrypts → JSON; running the bot has Rust decrypt + inject into
// the subprocess env at run time.

export interface AtwSettings {
  email: string;
  hasPassword: boolean;
  passwordDekVersion: number | null;
  botDir: string | null;
  browserExecutablePath: string | null;
  cadenceSeconds: number;
  repostDays: number;
  scheduleStartHour: number;
  scheduleEndHour: number;
  utcOffset: number;
  delayMs: number;
  headless: boolean;
}

export interface SetAtwSettingsPayload {
  email: string;
  /**
   * `null` to leave existing ciphertext alone, `""` (empty) to clear,
   * or a non-empty string to encrypt + replace. Keystore must be
   * unlocked when sending a non-null value.
   */
  password: string | null;
  botDir: string | null;
  browserExecutablePath: string | null;
  cadenceSeconds: number;
  repostDays: number;
  scheduleStartHour: number;
  scheduleEndHour: number;
  utcOffset: number;
  delayMs: number;
  headless: boolean;
}

export interface AtwHealthCheck {
  nodeFound: boolean;
  nodePath: string | null;
  chromeFound: boolean;
  chromePath: string | null;
  botDirSet: boolean;
  botDirExists: boolean;
  botDirHasRepostJs: boolean;
  botDirHasNodeModules: boolean;
}

export interface RunOutcome {
  status: 'success' | 'failed';
  summary: string;
  logExcerpt: string;
  elapsedSeconds: number;
}

export async function getAtwSettings(): Promise<AtwSettings> {
  return invoke<AtwSettings>('get_atw_settings');
}

export async function setAtwSettings(payload: SetAtwSettingsPayload): Promise<AtwSettings> {
  return invoke<AtwSettings>('set_atw_settings', { payload });
}

export async function atwHealthCheck(): Promise<AtwHealthCheck> {
  return invoke<AtwHealthCheck>('atw_health_check');
}

export async function atwRunNow(): Promise<RunOutcome> {
  return invoke<RunOutcome>('atw_run_now');
}
