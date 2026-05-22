// Relocate dist/ to a fresh /tmp directory before each release build.
//
// Why: macOS 15 auto-attaches `com.apple.provenance` to executables on first
// run. Hardened-runtime codesign rejects it as "resource fork, Finder
// information, or similar detritus not allowed". `xattr -d com.apple.provenance`
// removes it cleanly on local volumes — but inside an iCloud-synced directory
// (e.g. ~/Documents/GitHub/...), the iCloud File Provider intercepts the xattr
// delete and silently no-ops it. The xattr stays, codesign fails.
//
// Building under /tmp/ (non-iCloud) lets xattr -d succeed and codesign passes.
// We expose this transparently by symlinking the project's dist/ to a fresh
// /tmp dir; artifacts appear in the conventional `dist/` path via the link.
//
// Cleanup: /tmp is wiped on reboot, so we don't actively purge old runs.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const projectDist = path.join(__dirname, '..', 'dist');
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'PurplePDF-dist-'));

try {
  fs.rmSync(projectDist, { recursive: true, force: true });
} catch {
  // already gone — fine
}
fs.symlinkSync(tmpRoot, projectDist);
console.log(`[predist] dist/ → ${tmpRoot}`);
