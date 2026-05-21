import type { OutlineNode } from './types';

interface Props {
  outline: OutlineNode[];
  onSelect: (pageNumber: number) => void;
}

export default function OutlineTree({ outline, onSelect }: Props): JSX.Element {
  if (outline.length === 0) {
    return <p className="empty">This document has no outline.</p>;
  }
  return (
    <ul className="outline" role="tree">
      {outline.map((n, i) => (
        <OutlineItem key={i} node={n} onSelect={onSelect} />
      ))}
    </ul>
  );
}

function OutlineItem({
  node,
  onSelect
}: {
  node: OutlineNode;
  onSelect: (pageNumber: number) => void;
}): JSX.Element {
  return (
    <li role="treeitem">
      <button
        type="button"
        className="outline-link"
        onClick={() => node.pageIndex !== null && onSelect(node.pageIndex + 1)}
        disabled={node.pageIndex === null}
      >
        {node.title}
      </button>
      {node.children.length > 0 && (
        <ul role="group">
          {node.children.map((c, i) => (
            <OutlineItem key={i} node={c} onSelect={onSelect} />
          ))}
        </ul>
      )}
    </li>
  );
}
