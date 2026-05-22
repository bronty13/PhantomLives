import { useMemo, useState } from 'react';
import type { NoteFolder } from '../../data/notes';

interface Props {
  title: string;
  folders: NoteFolder[];
  /** Folder id to disable in the picker (typically the folder being
   *  moved, plus its descendants — we compute the descendant set
   *  inline so callers only have to pass the source id). */
  excludeId?: number | null;
  currentParentId?: number | null;
  onPick: (folderId: number | null) => void;
  onCancel: () => void;
}

interface TreeNode { folder: NoteFolder; children: TreeNode[]; }

function buildTree(folders: NoteFolder[]): TreeNode[] {
  const byId = new Map<number, TreeNode>();
  for (const f of folders) byId.set(f.id, { folder: f, children: [] });
  const roots: TreeNode[] = [];
  for (const node of byId.values()) {
    if (node.folder.parentId == null) {
      roots.push(node);
    } else {
      const parent = byId.get(node.folder.parentId);
      if (parent) parent.children.push(node);
      else roots.push(node);
    }
  }
  return roots;
}

function collectDescendants(folders: NoteFolder[], rootId: number): Set<number> {
  const out = new Set<number>([rootId]);
  let added = true;
  while (added) {
    added = false;
    for (const f of folders) {
      if (f.parentId != null && out.has(f.parentId) && !out.has(f.id)) {
        out.add(f.id); added = true;
      }
    }
  }
  return out;
}

export function FolderPickerModal({
  title, folders, excludeId, currentParentId, onPick, onCancel,
}: Props) {
  const tree = useMemo(() => buildTree(folders), [folders]);
  const blocked = useMemo(
    () => excludeId != null ? collectDescendants(folders, excludeId) : new Set<number>(),
    [folders, excludeId],
  );
  const [hovered, setHovered] = useState<number | null>(null);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm"
      onClick={onCancel}
    >
      <div
        className="rounded-3xl bg-white shadow-2xl border border-black/10 p-5 w-[420px] max-w-[90vw] max-h-[80vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-3">
          <h3 className="display-font text-lg font-semibold persona-accent">{title}</h3>
          <button type="button" onClick={onCancel} className="opacity-50 hover:opacity-100 text-xl leading-none">×</button>
        </div>
        <div className="overflow-y-auto flex-1 border border-black/5 rounded-xl bg-black/[0.02]">
          <PickRow
            id={null}
            label="🌷 All notes (root)"
            depth={0}
            current={currentParentId == null}
            onPick={onPick}
            hovered={hovered}
            setHovered={setHovered}
          />
          {tree.map((n) => (
            <PickNode
              key={n.folder.id} node={n} depth={1}
              blocked={blocked} currentParentId={currentParentId ?? null}
              hovered={hovered} setHovered={setHovered}
              onPick={onPick}
            />
          ))}
        </div>
        <div className="text-[11px] opacity-60 mt-2 italic">
          Tip: greyed-out rows are blocked (a folder can't be moved into itself or its children).
        </div>
      </div>
    </div>
  );
}

function PickNode({
  node, depth, blocked, currentParentId, hovered, setHovered, onPick,
}: {
  node: TreeNode; depth: number;
  blocked: Set<number>; currentParentId: number | null;
  hovered: number | null; setHovered: (id: number | null) => void;
  onPick: (id: number | null) => void;
}) {
  const isBlocked = blocked.has(node.folder.id);
  return (
    <>
      <PickRow
        id={node.folder.id}
        label={`📁 ${node.folder.name}`}
        depth={depth}
        current={currentParentId === node.folder.id}
        blocked={isBlocked}
        onPick={onPick}
        hovered={hovered}
        setHovered={setHovered}
      />
      {node.children.map((c) => (
        <PickNode
          key={c.folder.id} node={c} depth={depth + 1}
          blocked={blocked} currentParentId={currentParentId}
          hovered={hovered} setHovered={setHovered}
          onPick={onPick}
        />
      ))}
    </>
  );
}

function PickRow({
  id, label, depth, current = false, blocked = false, onPick, hovered, setHovered,
}: {
  id: number | null; label: string; depth: number;
  current?: boolean; blocked?: boolean;
  onPick: (id: number | null) => void;
  hovered: number | null; setHovered: (id: number | null) => void;
}) {
  const key = id ?? -1;
  const isHovered = hovered === key;
  return (
    <button
      type="button"
      disabled={blocked}
      onClick={() => !blocked && onPick(id)}
      onMouseEnter={() => setHovered(key)}
      onMouseLeave={() => setHovered(null)}
      className="w-full text-left text-sm py-1.5 flex items-center transition"
      style={{
        paddingLeft: 12 + depth * 16,
        background: isHovered && !blocked ? 'rgb(var(--persona-primary) / 0.45)' : 'transparent',
        color: blocked ? 'rgb(var(--persona-text) / 0.35)' : 'rgb(var(--persona-text))',
        cursor: blocked ? 'not-allowed' : 'pointer',
        fontWeight: current ? 700 : 500,
      }}
    >
      <span>{label}</span>
      {current && <span className="ml-2 text-[10px] opacity-60">(current location)</span>}
      {blocked && id != null && <span className="ml-2 text-[10px]">(can't pick — descendant)</span>}
    </button>
  );
}
