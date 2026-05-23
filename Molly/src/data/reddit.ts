import { invoke } from '@tauri-apps/api/core';

// Phase 15 PR1-frontend — Reddit ops typed wrappers.
// Rust owns all SQL + validation; we just shuttle JSON.

export type Rotation = 'fresh' | 'soon' | 'wait';

export interface Subreddit {
  id: number;
  personaCode: string | null;
  name: string;
  tagId: number | null;
  verified: boolean;
  karmaReq: string;
  rotation: Rotation;
  lastPostedAt: string | null;
  notes: string;
  starred: boolean;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface SubredditInput {
  personaCode: string | null;
  name: string;
  tagId: number | null;
  verified: boolean;
  karmaReq: string;
  rotation: Rotation;
  notes: string;
}

export interface SubredditPost {
  id: number;
  personaCode: string | null;
  subredditId: number | null;
  subredditName: string;
  tagId: number | null;
  postedDate: string;   // YYYY-MM-DD
  notes: string;
  createdAt: string;
}

export interface SubredditPostInput {
  personaCode: string | null;
  subredditId: number | null;
  subredditName: string;
  tagId: number | null;
  postedDate: string;
  notes: string;
}

export interface Caption {
  id: number;
  personaCode: string | null;
  text: string;
  tagId: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface CaptionInput {
  personaCode: string | null;
  text: string;
  tagId: number | null;
}

const personaArg = (code: string | null) => (code === 'ALL' || code == null ? null : code);

export async function listSubreddits(personaCode: string | null): Promise<Subreddit[]> {
  return invoke<Subreddit[]>('list_subreddits', { personaCode: personaArg(personaCode) });
}
export async function createSubreddit(input: SubredditInput): Promise<number> {
  return invoke<number>('create_subreddit', { input });
}
export async function updateSubreddit(id: number, input: SubredditInput): Promise<void> {
  await invoke<void>('update_subreddit', { id, input });
}
export async function setSubredditStarred(id: number, starred: boolean): Promise<void> {
  await invoke<void>('set_subreddit_starred', { id, starred });
}
export async function setSubredditVerified(id: number, verified: boolean): Promise<void> {
  await invoke<void>('set_subreddit_verified', { id, verified });
}
export async function deleteSubreddit(id: number): Promise<void> {
  await invoke<void>('delete_subreddit', { id });
}
export async function markSubredditPosted(subredditId: number, postedDate: string): Promise<number> {
  return invoke<number>('mark_subreddit_posted', { subredditId, postedDate });
}

export async function listSubredditPostsInRange(
  from: string,
  to: string,
  personaCode: string | null,
): Promise<SubredditPost[]> {
  return invoke<SubredditPost[]>('list_subreddit_posts_in_range', {
    from,
    to,
    personaCode: personaArg(personaCode),
  });
}
export async function createSubredditPost(input: SubredditPostInput): Promise<number> {
  return invoke<number>('create_subreddit_post', { input });
}
export async function deleteSubredditPost(id: number): Promise<void> {
  await invoke<void>('delete_subreddit_post', { id });
}

export async function listCaptions(personaCode: string | null): Promise<Caption[]> {
  return invoke<Caption[]>('list_captions', { personaCode: personaArg(personaCode) });
}
export async function createCaption(input: CaptionInput): Promise<number> {
  return invoke<number>('create_caption', { input });
}
export async function updateCaption(id: number, input: CaptionInput): Promise<void> {
  await invoke<void>('update_caption', { id, input });
}
export async function deleteCaption(id: number): Promise<void> {
  await invoke<void>('delete_caption', { id });
}
