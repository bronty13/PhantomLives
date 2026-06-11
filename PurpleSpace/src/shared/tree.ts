/**
 * @file tree.ts — pure page-tree helpers (no Electron/React imports; unit-tested).
 */

export interface PageMeta {
  _id: string;
  title: string;
  type: 'doc' | 'database';
  parentId: string | null;
  order: number;
  icon: string | null;
  favorite: boolean;
  updatedAt: number;
}

export interface TreeNode extends PageMeta {
  children: TreeNode[];
}

/**
 * Build the sidebar tree from the flat page list. Children of database
 * pages (rows) are excluded — like Notion, rows live in the table, not the
 * page tree.
 */
export function buildTree(pages: PageMeta[]): TreeNode[] {
  const byId = new Map<string, TreeNode>();
  for (const p of pages) byId.set(p._id, { ...p, children: [] });

  const roots: TreeNode[] = [];
  for (const node of byId.values()) {
    const parent = node.parentId ? byId.get(node.parentId) : undefined;
    if (parent) {
      if (parent.type === 'database') continue; // rows: not in the tree
      parent.children.push(node);
    } else {
      roots.push(node);
    }
  }
  const sortRec = (nodes: TreeNode[]): void => {
    nodes.sort((a, b) => a.order - b.order || a._id.localeCompare(b._id));
    for (const n of nodes) sortRec(n.children);
  };
  sortRec(roots);
  return roots;
}

/** Breadcrumb chain root→…→page. Includes database ancestors (for rows). */
export function breadcrumb(pages: PageMeta[], id: string): PageMeta[] {
  const byId = new Map(pages.map((p) => [p._id, p]));
  const chain: PageMeta[] = [];
  let cur = byId.get(id);
  const seen = new Set<string>();
  while (cur && !seen.has(cur._id)) {
    seen.add(cur._id);
    chain.unshift(cur);
    cur = cur.parentId ? byId.get(cur.parentId) : undefined;
  }
  return chain;
}

/** Compute a fractional `order` for inserting at `index` among `siblings` (sorted). */
export function orderForIndex(siblings: { order: number }[], index: number): number {
  const GAP = 1024;
  if (siblings.length === 0) return GAP;
  if (index <= 0) return siblings[0].order - GAP;
  if (index >= siblings.length) return siblings[siblings.length - 1].order + GAP;
  return (siblings[index - 1].order + siblings[index].order) / 2;
}

/** True if `candidateId` is `id` itself or one of its descendants. */
export function isSelfOrDescendant(pages: PageMeta[], id: string, candidateId: string): boolean {
  if (id === candidateId) return true;
  const byId = new Map(pages.map((p) => [p._id, p]));
  let cur = byId.get(candidateId);
  const seen = new Set<string>();
  while (cur?.parentId && !seen.has(cur._id)) {
    seen.add(cur._id);
    if (cur.parentId === id) return true;
    cur = byId.get(cur.parentId);
  }
  return false;
}
