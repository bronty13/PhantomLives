#!/usr/bin/env node
// Notarize Purple PDF after electron-builder signs it.
//
// Triggered by electron-builder's `afterSign` hook. Skips silently if any of
// the required env vars are missing — this lets local builds succeed without
// a developer account.
//
// Required env vars (for actual notarization):
//   APPLE_ID                — developer Apple ID
//   APPLE_APP_SPECIFIC_PASSWORD — app-specific password generated at appleid.apple.com
//   APPLE_TEAM_ID           — 10-char team ID
//
// We use the modern `notarytool` workflow which Apple requires as of 2023.

const { existsSync } = require('node:fs');
const { join } = require('node:path');

exports.default = async function notarizing(context) {
  const { electronPlatformName, appOutDir } = context;
  if (electronPlatformName !== 'darwin') return;

  const appleId = process.env.APPLE_ID;
  const appPassword = process.env.APPLE_APP_SPECIFIC_PASSWORD;
  const teamId = process.env.APPLE_TEAM_ID;

  if (!appleId || !appPassword || !teamId) {
    console.log('[notarize] Skipping — APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID not set.');
    return;
  }

  // Lazy-require so missing dep doesn't break local builds.
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
  await notarize({
    tool: 'notarytool',
    appPath,
    appleId,
    appleIdPassword: appPassword,
    teamId
  });
  console.log('[notarize] Done.');
};
