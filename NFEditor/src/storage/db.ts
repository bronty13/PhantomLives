// Persistence: localStorage with an in-memory fallback (NOT IndexedDB — it hangs
// on file:// opaque origins). Drafts are small text (images are external URLs,
// never inlined), so localStorage is plenty.
//
// CRITICAL: every key is prefixed `nf.`. NFEditor and CalendarMaker are both hosted
// under https://bronty13.github.io/<path>/, and the Same-Origin Policy ignores the
// path — they share ONE localStorage namespace. A bare key would read/clobber the
// sibling app's data (and mis-fire its What's-New modal).

import type { NFDocument } from '../shared/model';

const K = {
  docs: 'nf.docs',
  lastSeenVersion: 'nf.lastSeenVersion',
  outputMode: 'nf.outputMode',
};

const mem = new Map<string, string>();
let useMem = false;

function rawGet(key: string): string | null {
  if (useMem) return mem.get(key) ?? null;
  try {
    return localStorage.getItem(key);
  } catch {
    useMem = true;
    return mem.get(key) ?? null;
  }
}

function rawSet(key: string, value: string): void {
  if (useMem) {
    mem.set(key, value);
    return;
  }
  try {
    localStorage.setItem(key, value);
  } catch {
    useMem = true;
    mem.set(key, value);
  }
}

function readDocs(): Record<string, NFDocument> {
  const raw = rawGet(K.docs);
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, NFDocument>;
  } catch {
    return {};
  }
}

function writeDocs(map: Record<string, NFDocument>): void {
  rawSet(K.docs, JSON.stringify(map));
}

/** All saved documents, newest-updated first. */
export function listDocuments(): NFDocument[] {
  return Object.values(readDocs()).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export function getDocument(id: string): NFDocument | undefined {
  return readDocs()[id];
}

export function saveDocument(doc: NFDocument): void {
  const map = readDocs();
  map[doc.id] = doc;
  writeDocs(map);
}

export function deleteDocument(id: string): void {
  const map = readDocs();
  delete map[id];
  writeDocs(map);
}

export function getLastSeenVersion(): string | null {
  return rawGet(K.lastSeenVersion);
}

export function setLastSeenVersion(version: string): void {
  rawSet(K.lastSeenVersion, version);
}

export function getOutputMode(): string | null {
  return rawGet(K.outputMode);
}

export function setOutputMode(mode: string): void {
  rawSet(K.outputMode, mode);
}
