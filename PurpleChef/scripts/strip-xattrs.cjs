// electron-builder afterPack hook: strip xattrs that codesign --options runtime
// rejects as "resource fork, Finder information, or similar detritus not allowed".
//
// On macOS 15 (Sequoia), the kernel auto-attaches `com.apple.provenance` to
// any executable the first time it runs. electron-builder's framework
// processing triggers that first-run, leaving provenance on every helper.
// Hardened-runtime codesign then refuses to sign. We strip it recursively
// here, right before electron-builder's signing pass.
//
// We use `find` + per-file `xattr -d` because `xattr -cr` aborts on the
// first protected xattr it can't remove, while `find -exec ... \\;` keeps
// going.
const { execSync } = require('node:child_process');

exports.default = async function stripXattrs(context) {
  // macOS-only: there are no xattrs to strip on Windows/Linux builds.
  if (context.electronPlatformName !== 'darwin') return;
  const appPath = `${context.appOutDir}/${context.packager.appInfo.productFilename}.app`;
  const q = JSON.stringify(appPath);
  try {
    execSync(
      `find ${q} \\( -type f -o -type d \\) -exec xattr -d com.apple.FinderInfo {} \\; -exec xattr -d com.apple.ResourceFork {} \\; -exec xattr -d com.apple.provenance {} \\; 2>/dev/null; true`,
      { stdio: 'inherit', shell: '/bin/bash' }
    );
    execSync(`xattr -cr ${q} 2>/dev/null; true`, {
      stdio: 'inherit',
      shell: '/bin/bash'
    });
    console.log(
      `[afterPack] xattrs stripped (FinderInfo + ResourceFork + provenance + -cr): ${appPath}`
    );
  } catch (err) {
    console.warn(`[afterPack] xattr strip failed for ${appPath}: ${err.message}`);
  }
};
