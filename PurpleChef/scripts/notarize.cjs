#!/usr/bin/env node
// Notarize Purple Chef after electron-builder signs it, then staple the
// ticket onto the .app so the DMG ships with offline Gatekeeper approval.
//
// Triggered by electron-builder's `afterSign` hook. Skips silently when no
// notarization credentials are present — local `./build-app.sh` dev builds
// (adhoc-signed, identity=null) must keep working without a developer
// account.
//
// Credential resolution, in order:
//   1. NOTARIZE_PROFILE       — a `notarytool store-credentials` keychain
//                               profile (the PhantomLives release-machine
//                               convention; see RELEASING.md).
//   2. APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID — explicit env.

const { existsSync } = require('node:fs');
const { join } = require('node:path');
const { execFileSync } = require('node:child_process');

exports.default = async function notarizing(context) {
  const { electronPlatformName, appOutDir } = context;
  if (electronPlatformName !== 'darwin') return;

  const profile = process.env.NOTARIZE_PROFILE;
  const appleId = process.env.APPLE_ID;
  const appPassword = process.env.APPLE_APP_SPECIFIC_PASSWORD;
  const teamId = process.env.APPLE_TEAM_ID;

  if (!profile && !(appleId && appPassword && teamId)) {
    console.log(
      '[notarize] Skipping — set NOTARIZE_PROFILE or APPLE_ID/APPLE_APP_SPECIFIC_PASSWORD/APPLE_TEAM_ID.'
    );
    return;
  }

  let notarize;
  try {
    notarize = require('@electron/notarize').notarize;
  } catch {
    console.warn('[notarize] @electron/notarize not installed; skipping. Run `npm i -D @electron/notarize`.');
    return;
  }

  const appName = context.packager.appInfo.productFilename;
  const appPath = join(appOutDir, `${appName}.app`);
  if (!existsSync(appPath)) {
    console.warn(`[notarize] App not found at ${appPath}; skipping.`);
    return;
  }

  console.log(`[notarize] Submitting ${appPath} to Apple…`);
  await notarize(
    profile
      ? { tool: 'notarytool', appPath, keychainProfile: profile }
      : { tool: 'notarytool', appPath, appleId, appleIdPassword: appPassword, teamId }
  );

  console.log('[notarize] Stapling ticket onto the .app…');
  execFileSync('xcrun', ['stapler', 'staple', appPath], { stdio: 'inherit' });
  console.log('[notarize] Done.');
};
