import { defineSchema, defineTable } from 'convex/server';
import { v } from 'convex/values';

/**
 * Notion-style model: everything is a page.
 *
 * - type 'doc'      — a regular block-content page.
 * - type 'database' — a table; its property definitions + view config live
 *                     in `dbPropsJson`. Its CHILD pages are its rows.
 * - rows            — 'doc' pages whose parent is a 'database'; their cell
 *                     values live in `rowValuesJson` (propId → value). A row
 *                     opens as a full page (icon, cover, blocks) like Notion.
 *
 * Block content is kept out of `pages` (in `documents`) so the sidebar tree
 * query stays light no matter how large pages get.
 */
export default defineSchema({
  pages: defineTable({
    title: v.string(),
    type: v.union(v.literal('doc'), v.literal('database')),
    parentId: v.optional(v.id('pages')),
    /** Fractional order among siblings. */
    order: v.number(),
    /** Emoji icon (single grapheme), or unset for the default glyph. */
    icon: v.optional(v.string()),
    /** Cover: `gradient:<key>` or a Convex storage id prefixed `storage:`. */
    cover: v.optional(v.string()),
    favorite: v.boolean(),
    inTrash: v.boolean(),
    trashedAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
    /** type 'database' only: JSON of { properties: PropDef[], sorts, filters }. */
    dbPropsJson: v.optional(v.string()),
    /** rows only: JSON map of propId → cell value. */
    rowValuesJson: v.optional(v.string())
  })
    .index('by_parent', ['parentId'])
    .searchIndex('search_title', { searchField: 'title' }),

  documents: defineTable({
    pageId: v.id('pages'),
    /** Serialized BlockNote Block[]. */
    blocksJson: v.string(),
    updatedAt: v.number()
  }).index('by_page', ['pageId'])
});
