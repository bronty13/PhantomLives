import { useEffect, useState } from 'react';
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
}

function TreeNode({ scanId, node, depth, focusId, onSelect }: NodeProps): JSX.Element {
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
}

export default function FolderTree({ scanId, root, focusId, onSelect }: Props): JSX.Element {
  return (
    <div className="folder-tree">
      <TreeNode scanId={scanId} node={root} depth={0} focusId={focusId} onSelect={onSelect} />
    </div>
  );
}
