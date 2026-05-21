import { describe, it, expect } from 'vitest';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { execFileSync, execSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_SRC = resolve(
  fileURLToPath(import.meta.url),
  '..',
  '..',
  '..',
  'scripts',
  'bump-and-log.mjs'
);

function makeRepo(): { root: string; script: string } {
  const root = mkdtempSync(join(tmpdir(), 'pp-bump-'));
  execSync('git init -q', { cwd: root });
  execSync('git config user.email t@example.com', { cwd: root });
  execSync('git config user.name Tester', { cwd: root });
  const project = join(root, 'PurplePDF');
  mkdirSync(project);
  mkdirSync(join(project, 'scripts'));
  const script = join(project, 'scripts', 'bump-and-log.mjs');
  copyFileSync(SCRIPT_SRC, script);
  writeFileSync(
    join(project, 'package.json'),
    JSON.stringify({ name: 'purple-pdf', version: '1.2.3' }, null, 2) + '\n'
  );
  writeFileSync(join(project, 'CHANGELOG.md'), '# Changelog\n\n');
  writeFileSync(join(root, 'README.md'), '# repo\n');
  execSync('git add -A && git commit -q -m initial', { cwd: root });
  return { root, script };
}

describe('bump-and-log', () => {
  it('skips when no PurplePDF files are staged', () => {
    const { root, script } = makeRepo();
    writeFileSync(join(root, 'README.md'), '# repo update\n');
    execSync('git add README.md', { cwd: root });
    execFileSync('node', [script], { cwd: root });
    const pkg = JSON.parse(readFileSync(join(root, 'PurplePDF', 'package.json'), 'utf8'));
    expect(pkg.version).toBe('1.2.3');
  });

  it('bumps patch and prepends a changelog entry when PurplePDF files staged', () => {
    const { root, script } = makeRepo();
    writeFileSync(join(root, 'PurplePDF', 'foo.txt'), 'hello\n');
    execSync('git add PurplePDF/foo.txt', { cwd: root });
    writeFileSync(join(root, '.git', 'COMMIT_EDITMSG'), 'add foo\n');
    execFileSync('node', [script], { cwd: root });
    const pkg = JSON.parse(readFileSync(join(root, 'PurplePDF', 'package.json'), 'utf8'));
    expect(pkg.version).toBe('1.2.4');
    const log = readFileSync(join(root, 'PurplePDF', 'CHANGELOG.md'), 'utf8');
    expect(log).toMatch(/## \[1\.2\.4\]/);
    expect(log).toContain('add foo');
  });

  it('honors SKIP_BUMP=1', () => {
    const { root, script } = makeRepo();
    writeFileSync(join(root, 'PurplePDF', 'foo.txt'), 'hello\n');
    execSync('git add PurplePDF/foo.txt', { cwd: root });
    execFileSync('node', [script], {
      cwd: root,
      env: { ...process.env, SKIP_BUMP: '1' }
    });
    const pkg = JSON.parse(readFileSync(join(root, 'PurplePDF', 'package.json'), 'utf8'));
    expect(pkg.version).toBe('1.2.3');
  });
});
