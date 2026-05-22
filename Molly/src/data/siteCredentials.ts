import { invoke } from '@tauri-apps/api/core';

// Phase 11: site credentials (sub-credentials per site).
//
// A single site can hold 1..N credentials. The legacy `sites.username`
// column is mirrored to/from the primary credential row by the Rust
// data layer so existing read paths (Molly Helper "Copy user") keep
// working unchanged.
//
// The plaintext password ONLY crosses the IPC boundary in two directions:
//   - `setCredentialPassword`: frontend → Rust (encrypts server-side)
//   - `revealCredentialPassword`: Rust → frontend (decrypts server-side)
// The frontend never touches the wrapped DEK.

export interface SiteCredential {
  id: number;
  siteId: number;
  label: string;
  username: string;
  hasPassword: boolean;
  passwordDekVersion: number | null;
  passwordUpdatedAt: string | null;
  isPrimary: boolean;
  sortOrder: number;
}

export async function listSiteCredentials(siteId: number): Promise<SiteCredential[]> {
  return invoke<SiteCredential[]>('list_site_credentials', { siteId });
}

export async function createSiteCredential(
  siteId: number,
  label: string,
): Promise<SiteCredential> {
  return invoke<SiteCredential>('create_site_credential', {
    payload: { siteId, label },
  });
}

export async function updateCredentialUsername(
  credentialId: number,
  username: string,
): Promise<void> {
  await invoke('update_credential_username', {
    payload: { credentialId, username },
  });
}

export async function updateCredentialLabel(
  credentialId: number,
  label: string,
): Promise<void> {
  await invoke('update_credential_label', {
    payload: { credentialId, label },
  });
}

export async function setCredentialPassword(
  credentialId: number,
  plaintext: string,
): Promise<void> {
  await invoke('set_credential_password', {
    payload: { credentialId, plaintext },
  });
}

export async function clearCredentialPassword(credentialId: number): Promise<void> {
  await invoke('clear_credential_password', { credentialId });
}

export async function revealCredentialPassword(credentialId: number): Promise<string> {
  return invoke<string>('reveal_credential_password', { credentialId });
}

export async function setCredentialPrimary(credentialId: number): Promise<void> {
  await invoke('set_credential_primary', { credentialId });
}

export async function deleteSiteCredential(credentialId: number): Promise<void> {
  await invoke('delete_site_credential', { credentialId });
}
