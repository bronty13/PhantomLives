import { describe, it, expect } from 'vitest';
import { isProtected, normalizePath, type GuardOpts } from '../../src/main/safety/protectedPaths';

const mac: GuardOpts = { platform: 'darwin', homeDir: '/Users/me' };
const win: GuardOpts = { platform: 'win32', homeDir: 'C:\\Users\\me' };

describe('normalizePath', () => {
  it('resolves .. and . and trailing slashes', () => {
    expect(normalizePath('/Users/me/../../System', 'darwin')).toBe('/system');
    expect(normalizePath('/Users/me/Downloads/', 'darwin')).toBe('/users/me/downloads');
  });
  it('lowercases on case-insensitive platforms', () => {
    expect(normalizePath('/Users/ME', 'darwin')).toBe('/users/me');
    expect(normalizePath('C:\\Windows', 'win32')).toBe('c:\\windows');
  });
  it('keeps case on linux', () => {
    expect(normalizePath('/Home/Me', 'linux')).toBe('/Home/Me');
  });
  it('cannot escape above the root with ..', () => {
    expect(normalizePath('/../../etc', 'darwin')).toBe('/etc');
  });
});

describe('isProtected (macOS)', () => {
  const cases: Array<[string, boolean]> = [
    ['/', true],
    ['/System', true],
    ['/System/Library', false], // descendant of /System is allowed
    ['/Library', true],
    ['/Library/Caches/foo', false],
    ['/Users', true],
    ['/Users/me', true], // home root itself
    ['/Users/me/Downloads/big.zip', false],
    ['/Users/me/Library/Caches/app', false],
    ['/Users/me/../../System', true], // traversal lands on /System
    ['relative/path', true], // non-absolute
    ['', true]
  ];
  for (const [path, blocked] of cases) {
    it(`${path || '(empty)'} -> ${blocked ? 'blocked' : 'allowed'}`, () => {
      expect(isProtected(path, mac).blocked).toBe(blocked);
    });
  }
});

describe('isProtected (Windows)', () => {
  const cases: Array<[string, boolean]> = [
    ['C:\\', true],
    ['C:\\Windows', true],
    ['c:\\windows', true], // case-insensitive
    ['C:\\Windows\\System32\\drivers', false],
    ['C:\\Program Files', true],
    ['C:\\Users', true],
    ['C:\\Users\\me', true],
    ['C:\\Users\\me\\Downloads\\big.zip', false],
    ['\\\\server\\share', true],
    ['..\\..\\Windows', true]
  ];
  for (const [path, blocked] of cases) {
    it(`${path} -> ${blocked ? 'blocked' : 'allowed'}`, () => {
      expect(isProtected(path, win).blocked).toBe(blocked);
    });
  }
});

describe('isProtected app dirs', () => {
  it('blocks the app support and backup dirs', () => {
    const opts: GuardOpts = {
      ...mac,
      appSupportDir: '/Users/me/Library/Application Support/Purple Tree',
      backupDir: '/Users/me/Downloads/Purple Tree backup'
    };
    expect(isProtected('/Users/me/Library/Application Support/Purple Tree', opts).blocked).toBe(true);
    expect(isProtected('/Users/me/Downloads/Purple Tree backup', opts).blocked).toBe(true);
    // but a file *inside* a normal Downloads subfolder is fine
    expect(isProtected('/Users/me/Downloads/notes.txt', opts).blocked).toBe(false);
  });
});
