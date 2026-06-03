/**
 * @file protectedPaths.ts — the delete safety guard. PURE and unit-tested.
 *
 * Enforced in the main process inside the delete IPC handler — a renderer
 * "I checked it" flag is never trusted. The guard blocks deleting (or
 * deleting anything that *contains*) a filesystem root, an OS system folder,
 * the user's home root, or the app's own data/backup directories.
 *
 * Rule: a target is blocked if it equals a protected path, OR it is an
 * ancestor of one (removing it would take the protected location with it).
 * Descendants of a protected path are allowed — you *can* delete a specific
 * file inside ~/Library/Caches.
 */

export interface GuardOpts {
  platform: NodeJS.Platform;
  homeDir: string;
  /** App's Application Support dir — never deletable by this tool. */
  appSupportDir?: string;
  /** App's backup dir — never deletable by this tool. */
  backupDir?: string;
}

export interface GuardResult {
  blocked: boolean;
  reason?: string;
}

const caseInsensitive = (platform: NodeJS.Platform): boolean =>
  platform === 'win32' || platform === 'darwin';

/** Normalize a path for comparison: resolve ./.., unify separators, dedupe. */
export function normalizePath(p: string, platform: NodeJS.Platform): string {
  if (!p) return '';
  const win = platform === 'win32';
  let s = win ? p.replace(/\//g, '\\') : p;
  const sep = win ? '\\' : '/';

  // Capture a root prefix so '..' can't escape above it.
  let root = '';
  let rest = s;
  if (win) {
    const drive = /^([a-zA-Z]:)\\?/.exec(s);
    const unc = /^\\\\[^\\]+\\[^\\]+\\?/.exec(s);
    if (unc) {
      root = unc[0].replace(/\\$/, '') + '\\';
      rest = s.slice(unc[0].length);
    } else if (drive) {
      root = drive[1] + '\\';
      rest = s.slice(drive[0].length);
    }
  } else {
    if (s.startsWith('/')) {
      root = '/';
      rest = s.slice(1);
    }
  }

  const segs = rest.split(sep);
  const out: string[] = [];
  for (const seg of segs) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') {
      if (out.length > 0) out.pop();
      continue;
    }
    out.push(seg);
  }
  s = root + out.join(sep);
  if (caseInsensitive(platform)) s = s.toLowerCase();
  // Strip trailing sep (but keep a bare root).
  if (s.length > root.length && s.endsWith(sep)) s = s.slice(0, -1);
  return s;
}

function isAncestor(ancestor: string, descendant: string, sep: string): boolean {
  if (ancestor === descendant) return false;
  const a = ancestor.endsWith(sep) ? ancestor : ancestor + sep;
  return descendant.startsWith(a);
}

/** Build the list of protected absolute paths for this platform. */
export function protectedList(opts: GuardOpts): string[] {
  const { platform, homeDir } = opts;
  const norm = (p: string): string => normalizePath(p, platform);
  const list: string[] = [];

  if (platform === 'win32') {
    // Common drive roots + Windows system locations.
    for (const d of ['C:\\', 'D:\\', 'E:\\']) list.push(norm(d));
    list.push(
      norm('C:\\Windows'),
      norm('C:\\Program Files'),
      norm('C:\\Program Files (x86)'),
      norm('C:\\ProgramData'),
      norm('C:\\Users')
    );
  } else {
    list.push(norm('/'));
    if (platform === 'darwin') {
      list.push(
        norm('/System'),
        norm('/Library'),
        norm('/Applications'),
        norm('/Users'),
        norm('/Volumes'),
        norm('/usr'),
        norm('/bin'),
        norm('/sbin'),
        norm('/etc'),
        norm('/private'),
        norm('/cores')
      );
    } else {
      list.push(
        norm('/usr'),
        norm('/bin'),
        norm('/sbin'),
        norm('/etc'),
        norm('/boot'),
        norm('/lib'),
        norm('/proc'),
        norm('/sys'),
        norm('/dev'),
        norm('/var'),
        norm('/home'),
        norm('/root')
      );
    }
  }

  if (homeDir) list.push(norm(homeDir)); // home root itself
  if (opts.appSupportDir) list.push(norm(opts.appSupportDir));
  if (opts.backupDir) list.push(norm(opts.backupDir));
  return list;
}

/** The guard. Returns `{blocked:true, reason}` for anything unsafe to delete. */
export function isProtected(target: string, opts: GuardOpts): GuardResult {
  const sep = opts.platform === 'win32' ? '\\' : '/';
  const norm = normalizePath(target, opts.platform);
  if (!norm) return { blocked: true, reason: 'Empty or relative path' };

  // Reject anything that isn't an absolute path — never operate on a
  // relative target (it could resolve anywhere).
  const isAbsolute =
    opts.platform === 'win32'
      ? /^[a-z]:\\/.test(norm) || /^\\\\/.test(norm)
      : norm.startsWith('/');
  if (!isAbsolute) return { blocked: true, reason: `Refusing a non-absolute path: ${target}` };

  // A bare filesystem/drive root.
  const isRoot =
    norm === '/' || /^[a-z]:\\?$/.test(norm) || /^\\\\[^\\]+\\[^\\]+\\?$/.test(norm);
  if (isRoot) return { blocked: true, reason: `Refusing to touch a filesystem root: ${target}` };

  for (const prot of protectedList(opts)) {
    if (norm === prot) {
      return { blocked: true, reason: `Refusing to delete a protected location: ${target}` };
    }
    if (isAncestor(norm, prot, sep)) {
      return {
        blocked: true,
        reason: `Refusing to delete ${target} — it contains the protected location ${prot}`
      };
    }
  }
  return { blocked: false };
}
