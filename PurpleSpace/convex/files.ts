import { query, mutation } from './_generated/server';
import { v } from 'convex/values';

/** One-shot upload URL for the renderer (images, covers). */
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => ctx.storage.generateUploadUrl()
});

export const getUrl = query({
  args: { storageId: v.id('_storage') },
  handler: async (ctx, { storageId }) => ctx.storage.getUrl(storageId)
});
