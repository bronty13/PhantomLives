import { query, mutation } from './_generated/server';
import { v } from 'convex/values';

/** Block content for a page (null until first save). */
export const get = query({
  args: { pageId: v.id('pages') },
  handler: async (ctx, { pageId }) => {
    const doc = await ctx.db
      .query('documents')
      .withIndex('by_page', (q) => q.eq('pageId', pageId))
      .unique();
    return doc ? { blocksJson: doc.blocksJson, updatedAt: doc.updatedAt } : null;
  }
});

export const save = mutation({
  args: { pageId: v.id('pages'), blocksJson: v.string() },
  handler: async (ctx, { pageId, blocksJson }) => {
    const now = Date.now();
    const doc = await ctx.db
      .query('documents')
      .withIndex('by_page', (q) => q.eq('pageId', pageId))
      .unique();
    if (doc) {
      await ctx.db.patch(doc._id, { blocksJson, updatedAt: now });
    } else {
      await ctx.db.insert('documents', { pageId, blocksJson, updatedAt: now });
    }
    await ctx.db.patch(pageId, { updatedAt: now });
  }
});
