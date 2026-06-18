// Core types and platform constants shared by the pure logic (serializers,
// validators, schema) and the UI. Everything here is framework-free.

/** A NiteFlirt document is either a Flirt Profile or a Listing. */
export type DocType = 'profile' | 'listing';

/** Two output flavors from one document. `legacy` is <table>/<font>; `compact`
 *  is inline-style. The same global mode drives BOTH font and container flavor. */
export type OutputMode = 'compact' | 'legacy';

/** Hard character limits NiteFlirt enforces on submitted HTML. */
export const CHAR_LIMITS: Record<DocType, number> = {
  profile: 7_000,
  listing: 14_000,
};

/** Preview/layout widths. Profiles render at a fixed 800px; Listings cap at 820px.
 *  Responsive preview panes are rendered at the platform's documented breakpoints. */
export const PREVIEW_BREAKPOINTS = [375, 800, 1075] as const;
export const PROFILE_WIDTH = 800;
export const LISTING_MAX_WIDTH = 820;

/** The discrete NiteFlirt <font size> ladder. This — not arbitrary pt — is the
 *  canonical font-size representation in the document, because `<font size>` can
 *  only express these seven steps. */
export type NFSize = 1 | 2 | 3 | 4 | 5 | 6 | 7;
export const NF_SIZES: NFSize[] = [1, 2, 3, 4, 5, 6, 7];
export const SIZE_PT: Record<NFSize, number> = {
  1: 8,
  2: 10,
  3: 12,
  4: 14,
  5: 18,
  6: 24,
  7: 36,
};
export const DEFAULT_SIZE: NFSize = 3;

/** `12` -> `"12pt"`. */
export function ptString(size: NFSize): string {
  return `${SIZE_PT[size]}pt`;
}

// ---- Document JSON (ProseMirror / Tiptap shape, declared locally so the pure
// serializer can be unit-tested without importing the editor) ----------------

export interface DocMark {
  type: string;
  attrs?: Record<string, unknown>;
}

export interface DocNode {
  type: string;
  attrs?: Record<string, unknown>;
  content?: DocNode[];
  marks?: DocMark[];
  text?: string;
}

/** A saved listing/profile draft (persisted in localStorage). */
export interface NFDocument {
  id: string;
  name: string;
  docType: DocType;
  /** The ProseMirror doc JSON (top node is `{ type: 'doc', content: [...] }`). */
  content: DocNode;
  createdAt: string;
  updatedAt: string;
}

/** App-level UI version. Kept equal to package.json `version` (release hygiene). */
export const APP_VERSION = '0.1.0';
