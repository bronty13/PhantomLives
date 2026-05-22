import { invoke } from '@tauri-apps/api/core';

// Phase 13 — Notes data layer. Typed wrappers for the Rust commands.

export interface NoteFolder {
  id: number;
  parentId: number | null;
  name: string;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface NoteSummary {
  id: number;
  folderId: number | null;
  title: string;
  paperColor: string | null;
  fontFamily: string | null;
  updatedAt: string;
  lastEditedAt: string;
  tagIds: number[];
  attachmentCount: number;
}

export interface Note {
  id: number;
  folderId: number | null;
  title: string;
  contentHtml: string;
  contentText: string;
  paperColor: string | null;
  fontFamily: string | null;
  createdAt: string;
  updatedAt: string;
  lastEditedAt: string;
  tagIds: number[];
}

export interface NoteTag {
  id: number;
  name: string;
  color: string;
  sortOrder: number;
  isBuiltin: boolean;
}

export interface FindHit {
  noteId: number;
  noteTitle: string;
  folderId: number | null;
  lineNo: number;
  snippet: string;
}

export interface NoteDefaults {
  defaultFont: string;
  defaultPaperColor: string;
}

// ----- folders ---------------------------------------------------------------

export async function listNoteFolders(): Promise<NoteFolder[]> {
  return invoke<NoteFolder[]>('list_note_folders');
}
export async function createNoteFolder(parentId: number | null, name: string): Promise<number> {
  return invoke<number>('create_note_folder', { parentId, name });
}
export async function renameNoteFolder(folderId: number, name: string): Promise<void> {
  await invoke('rename_note_folder', { folderId, name });
}
export async function moveNoteFolder(folderId: number, newParentId: number | null): Promise<void> {
  await invoke('move_note_folder', { folderId, newParentId });
}
export async function deleteNoteFolder(folderId: number): Promise<void> {
  await invoke('delete_note_folder', { folderId });
}

// ----- notes -----------------------------------------------------------------

export async function listNotes(folderId: number | null): Promise<NoteSummary[]> {
  return invoke<NoteSummary[]>('list_notes', { folderId });
}
export async function getNote(noteId: number): Promise<Note> {
  return invoke<Note>('get_note', { noteId });
}
export async function createNote(folderId: number | null, title: string): Promise<number> {
  return invoke<number>('create_note', { folderId, title });
}
export async function updateNote(
  noteId: number, title: string, contentHtml: string, contentText: string,
): Promise<void> {
  await invoke('update_note', {
    payload: { noteId, title, contentHtml, contentText },
  });
}
export async function setNoteStyle(
  noteId: number, fontFamily: string | null, paperColor: string | null,
): Promise<void> {
  await invoke('set_note_style', { payload: { noteId, fontFamily, paperColor } });
}
export async function moveNote(noteId: number, newFolderId: number | null): Promise<void> {
  await invoke('move_note', { noteId, newFolderId });
}
export async function deleteNote(noteId: number): Promise<void> {
  await invoke('delete_note', { noteId });
}
export async function copyNote(noteId: number): Promise<number> {
  return invoke<number>('copy_note', { noteId });
}

// ----- tags ------------------------------------------------------------------

export async function listNoteTags(): Promise<NoteTag[]> {
  return invoke<NoteTag[]>('list_note_tags');
}
export async function createNoteTag(name: string, color: string): Promise<number> {
  return invoke<number>('create_note_tag', { name, color });
}
export async function updateNoteTag(tagId: number, name: string, color: string): Promise<void> {
  await invoke('update_note_tag', { tagId, name, color });
}
export async function deleteNoteTag(tagId: number): Promise<void> {
  await invoke('delete_note_tag', { tagId });
}
export async function setNoteTags(noteId: number, tagIds: number[]): Promise<void> {
  await invoke('set_note_tags', { noteId, tagIds });
}

// ----- search + find ---------------------------------------------------------

export async function searchNoteTitles(query: string, regex: boolean): Promise<NoteSummary[]> {
  return invoke<NoteSummary[]>('search_note_titles', { query, regex });
}
export async function findInNotes(query: string, regex: boolean): Promise<FindHit[]> {
  return invoke<FindHit[]>('find_in_notes', { query, regex });
}

// ----- defaults --------------------------------------------------------------

export async function getNoteDefaults(): Promise<NoteDefaults> {
  return invoke<NoteDefaults>('get_note_defaults');
}
export async function setNoteDefaults(defaults: NoteDefaults): Promise<void> {
  await invoke('set_note_defaults', { defaults });
}
