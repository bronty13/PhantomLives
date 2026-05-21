import { app } from 'electron';
import { mkdir, readdir, stat, unlink, writeFile, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

export function autosaveDir(): string {
  return join(app.getPath('userData'), 'autosaves');
}

/** Stable filename per source path; safe across reopens of the same file. */
function autosaveName(sourcePath: string | null, name: string): string {
  const key = sourcePath ?? `untitled:${name}`;
  const hash = createHash('sha1').update(key).digest('hex').slice(0, 16);
  return `${hash}.pdf`;
}

export interface AutosaveMeta {
  file: string;
  sourcePath: string | null;
  sourceName: string;
  mtimeMs: number;
  size: number;
}

const META_SUFFIX = '.json';

export async function writeAutosave(args: {
  bytes: Uint8Array;
  sourcePath: string | null;
  sourceName: string;
}): Promise<string> {
  const dir = autosaveDir();
  await mkdir(dir, { recursive: true });
  const fname = autosaveName(args.sourcePath, args.sourceName);
  const fpath = join(dir, fname);
  await writeFile(fpath, args.bytes);
  const meta = {
    sourcePath: args.sourcePath,
    sourceName: args.sourceName,
    savedAt: Date.now()
  };
  await writeFile(fpath + META_SUFFIX, JSON.stringify(meta));
  return fpath;
}

export async function clearAutosave(sourcePath: string | null, sourceName: string): Promise<void> {
  const dir = autosaveDir();
  const fpath = join(dir, autosaveName(sourcePath, sourceName));
  if (existsSync(fpath)) await unlink(fpath).catch(() => undefined);
  if (existsSync(fpath + META_SUFFIX)) await unlink(fpath + META_SUFFIX).catch(() => undefined);
}

export async function listAutosaves(): Promise<AutosaveMeta[]> {
  const dir = autosaveDir();
  if (!existsSync(dir)) return [];
  const entries = await readdir(dir);
  const out: AutosaveMeta[] = [];
  for (const f of entries) {
    if (!f.endsWith('.pdf')) continue;
    const full = join(dir, f);
    const st = await stat(full).catch(() => null);
    if (!st) continue;
    let meta: { sourcePath: string | null; sourceName: string } = {
      sourcePath: null,
      sourceName: f
    };
    const metaPath = full + META_SUFFIX;
    if (existsSync(metaPath)) {
      try {
        const raw = await readFile(metaPath, 'utf8');
        meta = JSON.parse(raw);
      } catch {
        // keep defaults
      }
    }
    out.push({
      file: full,
      sourcePath: meta.sourcePath,
      sourceName: meta.sourceName,
      mtimeMs: st.mtimeMs,
      size: st.size
    });
  }
  out.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return out;
}
