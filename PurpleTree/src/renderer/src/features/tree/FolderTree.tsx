import { useEffect, useState, type MouseEvent } from 'react';
import type { NodeRow } from '../../../../shared/types';
import { formatBytes } from '../common/format';

const api = window.purpleTree;
const SORT = { key: 'size', dir: 'desc' } as const;
const CHILD_LIMIT = 500;

interface NodeProps {
  scanId: string;
  node: NodeRow;
  depth: number;
  focusId: number;
  onSelect: (id: number) => void;
  onContext: (e: MouseEvent, node: NodeRow) => void;
}

function TreeNode({ scanId, node, depth, focusId, onSelect, onContext }: NodeProps): JSX.Element {
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
  return (
    <div className="tree-node">
      <div
        className={`tree-row${node.id === focusId ? ' selected' : ''}`}
        style={{ paddingLeft: depth * 14 + 4 }}
        onClick={() => onSelect(node.id)}
        onContextMenu={(e) => onContext(e, node)}
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
      {open && kids && (
        <div className="tree-children">
          {kids.map((k) => (
            <TreeNode
              key={k.id}
              scanId={scanId}
              node={k}
              depth={depth + 1}
              focusId={focusId}
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
  onSelect: (id: number) => void;
  onRefresh: (id: number) => void;
}

interface CtxMenu {
  x: number;
  y: number;
  id: number;
  path: string;
}

export default function FolderTree({ scanId, root, focusId, onSelect, onRefresh }: Props): JSX.Element {
  const [menu, setMenu] = useState<CtxMenu | null>(null);

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

  const openContext = (e: MouseEvent, node: NodeRow): void => {
    e.preventDefault();
    if (!node.isDir) return; // only folders can be refreshed
    setMenu({ x: e.clientX, y: e.clientY, id: node.id, path: node.path });
  };

  return (
    <div className="folder-tree">
      <TreeNode
        scanId={scanId}
        node={root}
        depth={0}
        focusId={focusId}
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
        </div>
      )}
    </div>
  );
}
