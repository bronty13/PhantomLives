import { useEffect, useState, type MouseEvent } from 'react';
import type { NodeRow, DeleteResult } from '../../../../shared/types';
import { formatBytes } from '../common/format';
import DeleteConfirm from '../delete/DeleteConfirm';

const api = window.purpleTree;
const SORT = { key: 'size', dir: 'desc' } as const;
const CHILD_LIMIT = 500;

interface NodeProps {
  scanId: string;
  node: NodeRow;
  depth: number;
  focusId: number;
  removed: Set<string>;
  onSelect: (id: number) => void;
  onContext: (e: MouseEvent, node: NodeRow, isRoot: boolean) => void;
}

function TreeNode({ scanId, node, depth, focusId, removed, onSelect, onContext }: NodeProps): JSX.Element {
  const [open, setOpen] = useState(depth === 0);
  const [kids, setKids] = useState<NodeRow[] | null>(null);

  useEffect(() => {
    if (!open || kids || !node.isDir) return;
    let cancelled = false;
    void api.getChildren(scanId, node.id, SORT, CHILD_LIMIT, 0).then((c) => {
      if (!cancelled) setKids(c.filter((k) => k.isDir));
    });
    return () => {
      cancelled = true;
    };
  }, [open, kids, node.id, node.isDir, scanId]);

  const expandable = node.isDir && node.childCount > 0;
  // Hide children the user just trashed/deleted; filter at render so the
  // removal shows instantly without refetching (the tree isn't pruned).
  const visibleKids = kids?.filter((k) => !removed.has(k.path)) ?? null;
  return (
    <div className="tree-node">
      <div
        className={`tree-row${node.id === focusId ? ' selected' : ''}`}
        style={{ paddingLeft: depth * 14 + 4 }}
        onClick={() => onSelect(node.id)}
        onContextMenu={(e) => onContext(e, node, depth === 0)}
      >
        <button
          className={`tree-twisty${expandable ? '' : ' hidden'}`}
          onClick={(e) => {
            e.stopPropagation();
            setOpen((o) => !o);
          }}
        >
          {expandable ? (open ? '▾' : '▸') : ''}
        </button>
        <span className="tree-icon">{node.isDir ? '📁' : '📄'}</span>
        <span className="tree-name" title={node.path}>
          {depth === 0 ? node.path : node.name}
        </span>
        <span className="tree-size">{formatBytes(node.aggSize)}</span>
      </div>
      {open && visibleKids && (
        <div className="tree-children">
          {visibleKids.map((k) => (
            <TreeNode
              key={k.id}
              scanId={scanId}
              node={k}
              depth={depth + 1}
              focusId={focusId}
              removed={removed}
              onSelect={onSelect}
              onContext={onContext}
            />
          ))}
        </div>
      )}
    </div>
  );
}

interface Props {
  scanId: string;
  root: NodeRow;
  focusId: number;
  allowPermanent: boolean;
  removed: Set<string>;
  onSelect: (id: number) => void;
  onRefresh: (id: number) => void;
  onDeleted: (paths: string[]) => void;
}

interface CtxMenu {
  x: number;
  y: number;
  id: number;
  path: string;
  isRoot: boolean;
}

export default function FolderTree({ scanId, root, focusId, allowPermanent, removed, onSelect, onRefresh, onDeleted }: Props): JSX.Element {
  const [menu, setMenu] = useState<CtxMenu | null>(null);
  const [confirm, setConfirm] = useState<string[] | null>(null);

  // Dismiss the context menu on any click, scroll, or Escape.
  useEffect(() => {
    if (!menu) return;
    const close = (): void => setMenu(null);
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') setMenu(null);
    };
    window.addEventListener('click', close);
    window.addEventListener('scroll', close, true);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('click', close);
      window.removeEventListener('scroll', close, true);
      window.removeEventListener('keydown', onKey);
    };
  }, [menu]);

  const openContext = (e: MouseEvent, node: NodeRow, isRoot: boolean): void => {
    e.preventDefault();
    if (!node.isDir) return; // only folders appear in the tree
    setMenu({ x: e.clientX, y: e.clientY, id: node.id, path: node.path, isRoot });
  };

  return (
    <div className="folder-tree">
      <TreeNode
        scanId={scanId}
        node={root}
        depth={0}
        focusId={focusId}
        removed={removed}
        onSelect={onSelect}
        onContext={openContext}
      />
      {menu && (
        <div
          className="ctx-menu"
          style={{ left: menu.x, top: menu.y }}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            className="ctx-item"
            onClick={() => {
              onRefresh(menu.id);
              setMenu(null);
            }}
          >
            ⟳ Refresh this folder
          </button>
          <button
            className="ctx-item"
            onClick={() => {
              void api.reveal(menu.path);
              setMenu(null);
            }}
          >
            📍 Reveal in Finder
          </button>
          {!menu.isRoot && (
            <button
              className="ctx-item danger"
              onClick={() => {
                setConfirm([menu.path]);
                setMenu(null);
              }}
            >
              🗑 Delete…
            </button>
          )}
        </div>
      )}
      {confirm && (
        <DeleteConfirm
          paths={confirm}
          allowPermanent={allowPermanent}
          onClose={() => setConfirm(null)}
          onDone={(result: DeleteResult) => {
            setConfirm(null);
            onDeleted(result.removed);
          }}
        />
      )}
    </div>
  );
}
