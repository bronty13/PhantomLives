// Helpers over the generated NASB tree (bible-data.ts). Verse selection supports
// a random pull and a book/chapter/verse picker.

import type { FillerEntry } from '../model/types';
import { BIBLE, BIBLE_BOOKS } from './bible-data';

export { BIBLE_BOOKS };

export interface BibleVerse {
  book: string;
  chapter: number; // 1-based
  verse: number; // 1-based
  text: string;
  reference: string; // 'John 3:16'
}

export function chapterCount(book: string): number {
  return BIBLE[book]?.length ?? 0;
}

export function verseCount(book: string, chapter: number): number {
  return BIBLE[book]?.[chapter - 1]?.length ?? 0;
}

export function getVerse(book: string, chapter: number, verse: number): BibleVerse | undefined {
  const text = BIBLE[book]?.[chapter - 1]?.[verse - 1];
  if (text == null || text === '') return undefined;
  return { book, chapter, verse, text, reference: `${book} ${chapter}:${verse}` };
}

/** Uniformly random verse across the whole Bible (weighted by verse count). */
export function getRandomVerse(rand: () => number = Math.random): BibleVerse {
  // Walk books, then chapters, picking a global verse index uniformly.
  let total = 0;
  for (const book of BIBLE_BOOKS) {
    for (const ch of BIBLE[book]) total += ch.length;
  }
  let target = Math.floor(rand() * total);
  for (const book of BIBLE_BOOKS) {
    const chapters = BIBLE[book];
    for (let c = 0; c < chapters.length; c++) {
      const verses = chapters[c];
      if (target < verses.length) {
        const v = target;
        return {
          book,
          chapter: c + 1,
          verse: v + 1,
          text: verses[v],
          reference: `${book} ${c + 1}:${v + 1}`,
        };
      }
      target -= verses.length;
    }
  }
  // Fallback (should be unreachable): John 3:16 if present, else first verse.
  return getVerse('John', 3, 16) ?? getVerse(BIBLE_BOOKS[0], 1, 1)!;
}

export function verseToFiller(v: BibleVerse): FillerEntry {
  return { id: `verse-${v.reference}`, kind: 'verse', text: v.text, reference: v.reference };
}

/** A random verse filler, avoiding `excludeRef` so a reroll visibly changes. */
export function randomVerseFiller(excludeRef?: string, rand: () => number = Math.random): FillerEntry {
  let v = getRandomVerse(rand);
  let guard = 0;
  while (excludeRef && v.reference === excludeRef && guard++ < 8) v = getRandomVerse(rand);
  return verseToFiller(v);
}
