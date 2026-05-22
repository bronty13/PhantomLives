import { useMemo, useState } from 'react';
import type { NoteFolder } from '../../data/notes';

interface Props {
  folders: NoteFolder[];
  selectedFolderId: number | null; // null = root view
  onSelect: (folderId: number | null) => void;
  onAction: (folderId: number | null, action: FolderAction) => void;
}

export type FolderAction = 'new-folder' | 'new-note' | 'rename' | 'move' | 'delete';

interface TreeNode { folder: NoteFolder; children: TreeNode[]; }

function buildTree(folders: NoteFolder[]): TreeNode[] {
  const byId = new Map<number, TreeNode>();
  for (const f of folders) byId.set(f.id, { folder: f, children: [] });
  const roots: TreeNode[] = [];
  for (const node of byId.values()) {
    const parentId = node.folder.parentId;
    if (parentId == null) {
      roots.push(node);
    } else {
      const parent = byId.get(parentId);
      if (parent) parent.children.push(node);
      else roots.push(node); // dangling parent — treat as root
    }
  }
  return roots;
}

export function FolderTree({ folders, selectedFolderId, onSelect, onAction }: Props) {
  const tree = useMemo(() => buildTree(folders), [folders]);
  return (
    <div className="space-y-0.5">
      <RootRow
        selected={selectedFolderId == null}
        onSelect={() => onSelect(null)}
        onAction={(a) => onAction(null, a)}
      />
      {tree.map((n) => (
        <TreeRow
          key={n.folder.id} node={n} depth={0}
          selectedFolderId={selectedFolderId}
          onSelect={onSelect} onAction={onAction}
        />
      ))}
    </div>
  );
}

function RootRow({ selected, onSelect, onAction }: {
  selected: boolean; onSelect: () => void; onAction: (a: FolderAction) => void;
}) {
  return (
    <Row
      depth={0}
      selected={selected}
      icon="🌷"
      label="All notes (root)"
      onSelect={onSelect}
      onAction={onAction}
      isRoot
    />
  );
}

function TreeRow({ node, depth, selectedFolderId, onSelect, onAction }: {
  node: TreeNode; depth: number;
  selectedFolderId: number | null;
  onSelect: (id: number | null) => void;
  onAction: (id: number | null, a: FolderAction) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  const hasChildren = node.children.length > 0;
  return (
    <>
      <Row
        depth={depth}
        selected={selectedFolderId === node.folder.id}
        icon={hasChildren ? (expanded ? '📂' : '📁') : '📁'}
        label={node.folder.name}
        chevron={hasChildren ? (expanded ? '▾' : '▸') : undefined}
        onChevronClick={hasChildren ? () => setExpanded((v) => !v) : undefined}
        onSelect={() => onSelect(node.folder.id)}
        onAction={(a) => onAction(node.folder.id, a)}
      />
      {expanded && node.children.map((c) => (
        <TreeRow
          key={c.folder.id} node={c} depth={depth + 1}
          selectedFolderId={selectedFolderId}
          onSelect={onSelect} onAction={onAction}
        />
      ))}
    </>
  );
}

function Row({
  depth, selected, icon, label, chevron, onChevronClick, onSelect, onAction, isRoot = false,
}: {
  depth: number;
  selected: boolean;
  icon: string;
  label: string;
  chevron?: string;
  onChevronClick?: () => void;
  onSelect: () => void;
  onAction: (a: FolderAction) => void;
  isRoot?: boolean;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  return (
    <div
      className="group flex items-center rounded-xl text-sm cursor-pointer transition relative"
      style={{
        background: selected ? 'rgb(var(--persona-primary) / 0.6)' : 'transparent',
        color: selected ? 'rgb(var(--persona-text))' : 'rgb(var(--persona-text) / 0.85)',
        fontWeight: selected ? 600 : 500,
        paddingLeft: 8 + depth * 16,
      }}
      onClick={onSelect}
    >
      {chevron ? (
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onChevronClick?.(); }}
          className="w-5 text-center opacity-60 hover:opacity-100"
        >
          {chevron}
        </button>
      ) : (
        <span className="w-5" />
      )}
      <span className="mr-1.5">{icon}</span>
      <span className="flex-1 truncate py-1.5">{label}</span>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); setMenuOpen((v) => !v); }}
        className="opacity-0 group-hover:opacity-70 hover:opacity-100 px-1.5 py-1 text-xs"
        title="Folder actions"
      >
        ⋯
      </button>
      {menuOpen && (
        <div
          className="absolute right-1 top-full mt-1 z-10 rounded-xl shadow-lg border border-black/10 bg-white text-left text-xs overflow-hidden"
          style={{ minWidth: 160 }}
          onClick={(e) => e.stopPropagation()}
        >
          <MenuItem onClick={() => { setMenuOpen(false); onAction('new-folder'); }}>＋ New folder</MenuItem>
          <MenuItem onClick={() => { setMenuOpen(false); onAction('new-note'); }}>＋ New note</MenuItem>
          {!isRoot && (
            <>
              <div className="border-t border-black/5" />
              <MenuItem onClick={() => { setMenuOpen(false); onAction('rename'); }}>Rename…</MenuItem>
              <MenuItem onClick={() => { setMenuOpen(false); onAction('move'); }}>Move to…</MenuItem>
              <div className="border-t border-black/5" />
              <MenuItem danger onClick={() => { setMenuOpen(false); onAction('delete'); }}>Delete folder</MenuItem>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function MenuItem({ children, onClick, danger = false }: {
  children: React.ReactNode; onClick: () => void; danger?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full text-left px-3 py-1.5 hover:bg-black/5"
      style={{ color: danger ? '#b91c1c' : 'inherit' }}
    >
      {children}
    </button>
  );
}
