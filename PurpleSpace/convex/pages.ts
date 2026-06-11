import { query, mutation, type MutationCtx } from './_generated/server';
import { v } from 'convex/values';
import type { Doc, Id } from './_generated/dataModel';

/** Gap between sibling `order` values; fractional inserts go between. */
const ORDER_GAP = 1024;

async function nextOrder(ctx: MutationCtx, parentId: Id<'pages'> | undefined): Promise<number> {
  const siblings = await ctx.db
    .query('pages')
    .withIndex('by_parent', (q) => q.eq('parentId', parentId))
    .collect();
  const max = siblings.reduce((m, s) => Math.max(m, s.order), 0);
  return max + ORDER_GAP;
}

/** Every non-trashed page, lean fields only — the client builds the tree. */
export const tree = query({
  args: {},
  handler: async (ctx) => {
    const pages = await ctx.db.query('pages').collect();
    return pages
      .filter((p) => !p.inTrash)
      .map((p) => ({
        _id: p._id,
        title: p.title,
        type: p.type,
        parentId: p.parentId ?? null,
        order: p.order,
        icon: p.icon ?? null,
        favorite: p.favorite,
        updatedAt: p.updatedAt
      }));
  }
});

export const get = query({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => ctx.db.get(id)
});

/** Rows of a database page (its non-trashed children), in creation order. */
export const rows = query({
  args: { databaseId: v.id('pages') },
  handler: async (ctx, { databaseId }) => {
    const children = await ctx.db
      .query('pages')
      .withIndex('by_parent', (q) => q.eq('parentId', databaseId))
      .collect();
    return children
      .filter((p) => !p.inTrash)
      .map((p) => ({
        _id: p._id,
        title: p.title,
        icon: p.icon ?? null,
        rowValuesJson: p.rowValuesJson ?? null,
        createdAt: p.createdAt
      }));
  }
});

export const trashList = query({
  args: {},
  handler: async (ctx) => {
    const pages = await ctx.db.query('pages').collect();
    return pages
      .filter((p) => p.inTrash)
      .sort((a, b) => (b.trashedAt ?? 0) - (a.trashedAt ?? 0))
      .map((p) => ({ _id: p._id, title: p.title, type: p.type, icon: p.icon ?? null, trashedAt: p.trashedAt ?? 0 }));
  }
});

export const search = query({
  args: { term: v.string() },
  handler: async (ctx, { term }) => {
    if (!term.trim()) return [];
    const hits = await ctx.db
      .query('pages')
      .withSearchIndex('search_title', (q) => q.search('title', term))
      .take(20);
    return hits
      .filter((p) => !p.inTrash)
      .map((p) => ({ _id: p._id, title: p.title, type: p.type, icon: p.icon ?? null, parentId: p.parentId ?? null }));
  }
});

export const create = mutation({
  args: {
    parentId: v.optional(v.id('pages')),
    type: v.union(v.literal('doc'), v.literal('database')),
    title: v.optional(v.string()),
    rowValuesJson: v.optional(v.string())
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const id = await ctx.db.insert('pages', {
      title: args.title ?? '',
      type: args.type,
      parentId: args.parentId,
      order: await nextOrder(ctx, args.parentId),
      favorite: false,
      inTrash: false,
      createdAt: now,
      updatedAt: now,
      dbPropsJson: args.type === 'database' ? defaultDbPropsJson() : undefined,
      rowValuesJson: args.rowValuesJson
    });
    return id;
  }
});

function defaultDbPropsJson(): string {
  return JSON.stringify({
    properties: [
      { id: 'title', name: 'Name', type: 'title' },
      { id: 'p_tags', name: 'Tags', type: 'multiSelect', options: [] },
      { id: 'p_date', name: 'Date', type: 'date' }
    ],
    sorts: [],
    filters: []
  });
}

export const rename = mutation({
  args: { id: v.id('pages'), title: v.string() },
  handler: async (ctx, { id, title }) => {
    await ctx.db.patch(id, { title, updatedAt: Date.now() });
  }
});

export const setIcon = mutation({
  args: { id: v.id('pages'), icon: v.optional(v.string()) },
  handler: async (ctx, { id, icon }) => {
    await ctx.db.patch(id, { icon, updatedAt: Date.now() });
  }
});

export const setCover = mutation({
  args: { id: v.id('pages'), cover: v.optional(v.string()) },
  handler: async (ctx, { id, cover }) => {
    await ctx.db.patch(id, { cover, updatedAt: Date.now() });
  }
});

export const toggleFavorite = mutation({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => {
    const page = await ctx.db.get(id);
    if (!page) return;
    await ctx.db.patch(id, { favorite: !page.favorite });
  }
});

export const setDbProps = mutation({
  args: { id: v.id('pages'), dbPropsJson: v.string() },
  handler: async (ctx, { id, dbPropsJson }) => {
    await ctx.db.patch(id, { dbPropsJson, updatedAt: Date.now() });
  }
});

export const setRowValues = mutation({
  args: { id: v.id('pages'), rowValuesJson: v.string() },
  handler: async (ctx, { id, rowValuesJson }) => {
    await ctx.db.patch(id, { rowValuesJson, updatedAt: Date.now() });
  }
});

/** Move a page to a new parent and/or position. `order` is the new fractional order. */
export const move = mutation({
  args: {
    id: v.id('pages'),
    parentId: v.optional(v.id('pages')),
    order: v.optional(v.number())
  },
  handler: async (ctx, { id, parentId, order }) => {
    // Refuse cycles: walk up from the new parent; it must not pass through `id`.
    let cursor = parentId;
    while (cursor) {
      if (cursor === id) return;
      const p = await ctx.db.get(cursor);
      cursor = p?.parentId;
    }
    await ctx.db.patch(id, {
      parentId,
      order: order ?? (await nextOrder(ctx, parentId)),
      updatedAt: Date.now()
    });
  }
});

async function collectSubtree(ctx: MutationCtx, rootId: Id<'pages'>): Promise<Doc<'pages'>[]> {
  const out: Doc<'pages'>[] = [];
  const queue: Id<'pages'>[] = [rootId];
  while (queue.length) {
    const id = queue.shift()!;
    const page = await ctx.db.get(id);
    if (!page) continue;
    out.push(page);
    const children = await ctx.db
      .query('pages')
      .withIndex('by_parent', (q) => q.eq('parentId', id))
      .collect();
    for (const c of children) queue.push(c._id);
  }
  return out;
}

export const trash = mutation({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => {
    const now = Date.now();
    for (const page of await collectSubtree(ctx, id)) {
      await ctx.db.patch(page._id, { inTrash: true, trashedAt: now, favorite: false });
    }
  }
});

export const restore = mutation({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => {
    const page = await ctx.db.get(id);
    if (!page) return;
    // If the original parent is itself still in the trash, restore to root.
    let parentId = page.parentId;
    if (parentId) {
      const parent = await ctx.db.get(parentId);
      if (!parent || parent.inTrash) parentId = undefined;
    }
    await ctx.db.patch(id, { inTrash: false, trashedAt: undefined, parentId });
    for (const sub of await collectSubtree(ctx, id)) {
      await ctx.db.patch(sub._id, { inTrash: false, trashedAt: undefined });
    }
  }
});

export const deleteForever = mutation({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => {
    for (const page of await collectSubtree(ctx, id)) {
      const doc = await ctx.db
        .query('documents')
        .withIndex('by_page', (q) => q.eq('pageId', page._id))
        .unique();
      if (doc) await ctx.db.delete(doc._id);
      if (page.cover?.startsWith('storage:')) {
        await ctx.storage.delete(page.cover.slice('storage:'.length) as Id<'_storage'>).catch(() => {});
      }
      await ctx.db.delete(page._id);
    }
  }
});

export const emptyTrash = mutation({
  args: {},
  handler: async (ctx) => {
    const pages = await ctx.db.query('pages').collect();
    for (const page of pages.filter((p) => p.inTrash)) {
      const doc = await ctx.db
        .query('documents')
        .withIndex('by_page', (q) => q.eq('pageId', page._id))
        .unique();
      if (doc) await ctx.db.delete(doc._id);
      await ctx.db.delete(page._id);
    }
  }
});

/** Deep-duplicate a page (content + subtree), placed right after the original. */
export const duplicate = mutation({
  args: { id: v.id('pages') },
  handler: async (ctx, { id }) => {
    const now = Date.now();
    async function copy(srcId: Id<'pages'>, parentId: Id<'pages'> | undefined, titleSuffix: string): Promise<Id<'pages'> | null> {
      const src = await ctx.db.get(srcId);
      if (!src) return null;
      const newId = await ctx.db.insert('pages', {
        title: src.title + titleSuffix,
        type: src.type,
        parentId,
        order: titleSuffix ? src.order + 1 : (await nextOrder(ctx, parentId)),
        icon: src.icon,
        cover: src.cover?.startsWith('storage:') ? undefined : src.cover,
        favorite: false,
        inTrash: false,
        createdAt: now,
        updatedAt: now,
        dbPropsJson: src.dbPropsJson,
        rowValuesJson: src.rowValuesJson
      });
      const doc = await ctx.db
        .query('documents')
        .withIndex('by_page', (q) => q.eq('pageId', srcId))
        .unique();
      if (doc) {
        await ctx.db.insert('documents', { pageId: newId, blocksJson: doc.blocksJson, updatedAt: now });
      }
      const children = await ctx.db
        .query('pages')
        .withIndex('by_parent', (q) => q.eq('parentId', srcId))
        .collect();
      for (const c of children.filter((c) => !c.inTrash).sort((a, b) => a.order - b.order)) {
        await copy(c._id, newId, '');
      }
      return newId;
    }
    const src = await ctx.db.get(id);
    return copy(id, src?.parentId, ' (copy)');
  }
});
