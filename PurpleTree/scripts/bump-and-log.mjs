#!/usr/bin/env node
/**
 * Auto-bump the patch version in PurpleTree/package.json and prepend an
 * entry to CHANGELOG.md using the staged commit message. Runs from the
 * git pre-commit hook installed by scripts/install-git-hooks.sh.
 *
 * - Only fires when the staged change set touches PurpleTree/** (so commits
 *   to sibling projects don't churn the app version).
 * - Reads commit subject from .git/COMMIT_EDITMSG (best-effort).
 * - Bumps package.json's patch version.
 * - Re-stages package.json and CHANGELOG.md so the bump is part of the commit.
 *
 * Pass --skip (or set SKIP_BUMP=1) to no-op.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, '..');

if (process.argv.includes('--skip') || process.env.SKIP_BUMP === '1') {
  process.exit(0);
}

let gitRoot;
try {
  gitRoot = execSync('git rev-parse --show-toplevel', { cwd: projectRoot })
    .toString()
    .trim();
} catch {
  process.exit(0);
}

// Only bump when the staged change set touches files under this project.
let staged = '';
try {
  staged = execSync('git diff --cached --name-only', { cwd: gitRoot }).toString();
} catch {
  process.exit(0);
}
const projectRel = relative(gitRoot, projectRoot).replaceAll('\\', '/');
const touchesProject = staged
  .split('\n')
  .map((s) => s.trim())
  .some((p) => p && (p === projectRel || p.startsWith(`${projectRel}/`)));
if (!touchesProject) process.exit(0);

const pkgPath = join(projectRoot, 'package.json');
const changelogPath = join(projectRoot, 'CHANGELOG.md');
const commitMsgPath = join(gitRoot, '.git', 'COMMIT_EDITMSG');

const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
const cur = String(pkg.version || '0.0.0');
const m = cur.match(/^(\d+)\.(\d+)\.(\d+)(.*)$/);
if (!m) {
  console.error(`bump-and-log: cannot parse version "${cur}"`);
  process.exit(0);
}
const next = `${m[1]}.${m[2]}.${Number(m[3]) + 1}`;
pkg.version = next;
writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');

let subject = '';
try {
  if (existsSync(commitMsgPath)) {
    subject =
      readFileSync(commitMsgPath, 'utf8')
        .split('\n')
        .find((l) => l.trim() && !l.startsWith('#'))
        ?.trim() ?? '';
  }
} catch {
  // ignore
}
if (!subject) subject = '(no commit message)';

const today = new Date().toISOString().slice(0, 10);
let log = existsSync(changelogPath) ? readFileSync(changelogPath, 'utf8') : '# Changelog\n\n';
const entry = `## [${next}] - ${today}\n\n- ${subject}\n\n`;

const firstSection = log.search(/^## \[/m);
if (firstSection > 0) {
  log = log.slice(0, firstSection) + entry + log.slice(firstSection);
} else {
  log = log.replace(/^(# .*\n+)/, (h) => h + entry);
  if (!log.includes(entry)) log = `# Changelog\n\n${entry}${log}`;
}
writeFileSync(changelogPath, log);

try {
  execSync(`git add "${pkgPath}" "${changelogPath}"`, { cwd: gitRoot, stdio: 'ignore' });
} catch (err) {
  console.error('bump-and-log: failed to re-stage files:', err.message);
}
console.log(`bump-and-log: ${cur} -> ${next}`);
