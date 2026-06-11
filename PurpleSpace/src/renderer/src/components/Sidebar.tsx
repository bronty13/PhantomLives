import React, { useState } from 'react';
import { useMutation, useQuery } from 'convex/react';
import { api } from '../../../../convex/_generated/api';
import type { Id } from '../../../../convex/_generated/dataModel';
import { orderForIndex, type PageMeta, type TreeNode } from '../../../shared/tree';
import {
  ChevronRight,
  Plus,
  Dots,
  PageGlyph,
  DatabaseGlyph,
  Star,
  TrashGlyph,
  SearchGlyph,
  GearGlyph,
  RenameGlyph,
  DuplicateGlyph,
  RestoreGlyph
} from '../lib/icons';
import { Menu, MenuItem, MenuSep, MenuNote, Popover } from './Popover';

interface SidebarProps {
  tree: TreeNode[];
  pages: PageMeta[];
  currentId: string | null;
  onNavigate: (id: string | null) => void;
  onNewPage: (type: 'doc' | 'database', parentId?: string) => Promise<void>;
  onOpenSearch: () => void;
  onOpenSettings: () => void;
  showToast: (msg: string) => void;
}

type DropPos = 'above' | 'below' | 'into';

interface RowMenuState {
  node: TreeNode;
  at: { x: number; y: number };
}

export default function Sidebar(props: SidebarProps): React.JSX.Element {
  const { tree, currentId, onNavigate, onNewPage, onOpenSearch, onOpenSettings, showToast } = props;

  const movePage = useMutation(api.pages.move);
  const renamePage = useMutation(api.pages.rename);
  const trashPage = useMutation(api.pages.trash);
  const duplicatePage = useMutation(api.pages.duplicate);
  const toggleFavorite = useMutation(api.pages.toggleFavorite);

  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());
  const [rowMenu, setRowMenu] = useState<RowMenuState | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  const [dragId, setDragId] = useState<string | null>(null);
  const [dropTarget, setDropTarget] = useState<{ id: string; pos: DropPos } | null>(null);
  const [trashAt, setTrashAt] = useState<{ x: number; y: number } | null>(null);

  const favorites = props.pages.filter((p) => p.favorite);

  const toggleExpand = (id: string): void => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleDrop = async (target: TreeNode, pos: DropPos, siblings: TreeNode[]): Promise<void> => {
    if (!dragId || dragId === target._id) return;
    // No dropping a page into its own subtree (server re-checks too).
    const inSubtree = (nodes: TreeNode[]): boolean =>
      nodes.some((n) => n._id === target._id || inSubtree(n.children));
    const dragNode = findNode(tree, dragId);
    if (dragNode && (target._id === dragId || inSubtree(dragNode.children))) return;

    if (pos === 'into') {
      await movePage({ id: dragId as Id<'pages'>, parentId: target._id as Id<'pages'> });
      setExpanded((prev) => new Set(prev).add(target._id));
    } else {
      const visible = siblings.filter((s) => s._id !== dragId);
      const idx = visible.findIndex((s) => s._id === target._id);
      const insertAt = pos === 'above' ? idx : idx + 1;
      await movePage({
        id: dragId as Id<'pages'>,
        parentId: (target.parentId ?? undefined) as Id<'pages'> | undefined,
        order: orderForIndex(visible, insertAt)
      });
    }
  };

  const renderRow = (node: TreeNode, depth: number, siblings: TreeNode[]): React.ReactNode => {
    const isOpen = expanded.has(node._id);
    const hasKids = node.children.length > 0;
    const active = node._id === currentId;
    const drop = dropTarget?.id === node._id ? dropTarget.pos : null;

    return (
      <div key={node._id}>
        <div
          className={`tree-row ${active ? 'active' : ''} ${drop ? `drop-${drop}` : ''}`}
          style={{ paddingLeft: 4 + depth * 14 }}
          draggable={renaming !== node._id}
          onClick={() => onNavigate(node._id)}
          onDragStart={(e) => {
            setDragId(node._id);
            e.dataTransfer.effectAllowed = 'move';
          }}
          onDragEnd={() => {
            setDragId(null);
            setDropTarget(null);
          }}
          onDragOver={(e) => {
            if (!dragId || dragId === node._id) return;
            e.preventDefault();
            const r = e.currentTarget.getBoundingClientRect();
            const t = (e.clientY - r.top) / r.height;
            const pos: DropPos = t < 0.3 ? 'above' : t > 0.7 ? 'below' : 'into';
            setDropTarget({ id: node._id, pos });
          }}
          onDragLeave={() => setDropTarget((d) => (d?.id === node._id ? null : d))}
          onDrop={(e) => {
            e.preventDefault();
            const target = dropTarget;
            setDropTarget(null);
            if (target?.id === node._id) void handleDrop(node, target.pos, siblings);
          }}
          onContextMenu={(e) => {
            e.preventDefault();
            setRowMenu({ node, at: { x: e.clientX, y: e.clientY } });
          }}
        >
          <button
            className={`tree-caret ${isOpen ? 'open' : ''}`}
            style={{ visibility: node.type === 'doc' || hasKids ? 'visible' : 'hidden' }}
            onClick={(e) => {
              e.stopPropagation();
              toggleExpand(node._id);
            }}
          >
            <ChevronRight />
          </button>
          <span className="tree-icon">
            {node.icon ?? (node.type === 'database' ? <DatabaseGlyph /> : <PageGlyph />)}
          </span>
          {renaming === node._id ? (
            <input
              type="text"
              autoFocus
              defaultValue={node.title}
              style={{
                flex: 1,
                minWidth: 0,
                font: 'inherit',
                border: 'none',
                outline: 'none',
                background: 'var(--paper-elev)',
                borderRadius: 4,
                padding: '0 4px'
              }}
              onClick={(e) => e.stopPropagation()}
              onBlur={(e) => {
                void renamePage({ id: node._id as Id<'pages'>, title: e.target.value });
                setRenaming(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === 'Escape') (e.target as HTMLInputElement).blur();
              }}
            />
          ) : (
            <span className={`tree-label ${node.title ? '' : 'untitled'}`}>
              {node.title || 'Untitled'}
            </span>
          )}
          <span className="tree-actions">
            <button
              className="tree-action"
              title="More actions"
              onClick={(e) => {
                e.stopPropagation();
                setRowMenu({ node, at: { x: e.clientX, y: e.clientY } });
              }}
            >
              <Dots size={13} />
            </button>
            {node.type === 'doc' && (
              <button
                className="tree-action"
                title="Add a page inside"
                onClick={(e) => {
                  e.stopPropagation();
                  setExpanded((prev) => new Set(prev).add(node._id));
                  void onNewPage('doc', node._id);
                }}
              >
                <Plus size={13} />
              </button>
            )}
          </span>
        </div>
        {isOpen && (
          <div className="tree-children">
            {node.type === 'database' ? (
              <div className="tree-empty-note" style={{ paddingLeft: 28 + depth * 14 }}>
                rows live in the table
              </div>
            ) : hasKids ? (
              node.children.map((c) => renderRow(c, depth + 1, node.children))
            ) : (
              <div className="tree-empty-note" style={{ paddingLeft: 28 + depth * 14 }}>
                No pages inside
              </div>
            )}
          </div>
        )}
      </div>
    );
  };

  return (
    <nav className="sidebar">
      <div className="sidebar-drag" />
      <div className="sidebar-scroll scrolly">
        <button className="nav-item" onClick={onOpenSearch}>
          <SearchGlyph />
          <span>Search</span>
          <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--ink-3)' }}>⌘P</span>
        </button>

        {favorites.length > 0 && (
          <div className="sidebar-section">
            <div className="sidebar-section-title">Favorites</div>
            {favorites.map((p) => (
              <div
                key={p._id}
                className={`tree-row ${p._id === currentId ? 'active' : ''}`}
                onClick={() => onNavigate(p._id)}
              >
                <span className="tree-caret" style={{ visibility: 'hidden' }} />
                <span className="tree-icon">
                  {p.icon ?? (p.type === 'database' ? <DatabaseGlyph /> : <PageGlyph />)}
                </span>
                <span className={`tree-label ${p.title ? '' : 'untitled'}`}>
                  {p.title || 'Untitled'}
                </span>
              </div>
            ))}
          </div>
        )}

        <div className="sidebar-section">
          <div className="sidebar-section-title">Pages</div>
          {tree.map((n) => renderRow(n, 0, tree))}
          <button className="nav-item" style={{ marginTop: 2 }} onClick={() => void onNewPage('doc')}>
            <Plus />
            <span>New page</span>
          </button>
        </div>
      </div>

      <div className="sidebar-footer">
        <button className="nav-item" onClick={() => void onNewPage('database')}>
          <DatabaseGlyph />
          <span>New database</span>
        </button>
        <button
          className="nav-item"
          onClick={(e) => setTrashAt({ x: e.clientX, y: e.clientY - 300 })}
        >
          <TrashGlyph />
          <span>Trash</span>
        </button>
        <button className="nav-item" onClick={onOpenSettings}>
          <GearGlyph />
          <span>Settings</span>
        </button>
      </div>

      {rowMenu && (
        <Menu at={rowMenu.at} onClose={() => setRowMenu(null)}>
          <MenuItem
            icon={<Star filled={rowMenu.node.favorite} />}
            label={rowMenu.node.favorite ? 'Remove from Favorites' : 'Add to Favorites'}
            onClick={() => void toggleFavorite({ id: rowMenu.node._id as Id<'pages'> })}
          />
          <MenuItem
            icon={<RenameGlyph />}
            label="Rename"
            onClick={() => setRenaming(rowMenu.node._id)}
          />
          <MenuItem
            icon={<DuplicateGlyph />}
            label="Duplicate"
            onClick={() => void duplicatePage({ id: rowMenu.node._id as Id<'pages'> })}
          />
          {rowMenu.node.type === 'doc' && (
            <MenuItem
              icon={<Plus />}
              label="Add page inside"
              onClick={() => {
                setExpanded((prev) => new Set(prev).add(rowMenu.node._id));
                void onNewPage('doc', rowMenu.node._id);
              }}
            />
          )}
          <MenuSep />
          <MenuItem
            icon={<TrashGlyph />}
            label="Move to Trash"
            danger
            onClick={() => {
              void trashPage({ id: rowMenu.node._id as Id<'pages'> });
              showToast(`Moved “${rowMenu.node.title || 'Untitled'}” to Trash`);
            }}
          />
        </Menu>
      )}

      {trashAt && (
        <TrashPopover at={trashAt} onClose={() => setTrashAt(null)} onNavigate={onNavigate} showToast={showToast} />
      )}
    </nav>
  );
}

function findNode(nodes: TreeNode[], id: string): TreeNode | null {
  for (const n of nodes) {
    if (n._id === id) return n;
    const sub = findNode(n.children, id);
    if (sub) return sub;
  }
  return null;
}

// ---- Trash ------------------------------------------------------------------

interface TrashPopoverProps {
  at: { x: number; y: number };
  onClose: () => void;
  onNavigate: (id: string) => void;
  showToast: (msg: string) => void;
}

function TrashPopover({ at, onClose, onNavigate, showToast }: TrashPopoverProps): React.JSX.Element {
  const items = useQuery(api.pages.trashList) as
    | { _id: string; title: string; type: 'doc' | 'database'; icon: string | null; trashedAt: number }[]
    | undefined;
  const restore = useMutation(api.pages.restore);
  const deleteForever = useMutation(api.pages.deleteForever);
  const emptyTrash = useMutation(api.pages.emptyTrash);

  return (
    <Popover at={at} onClose={onClose} className="menu">
      <MenuNote>Trash{items && items.length ? ` — ${items.length} page${items.length > 1 ? 's' : ''}` : ''}</MenuNote>
      <div style={{ maxHeight: 280, overflowY: 'auto' }}>
        {(items ?? []).map((p) => (
          <div key={p._id} className="opt-row">
            <span className="tree-icon">{p.icon ?? (p.type === 'database' ? <DatabaseGlyph /> : <PageGlyph />)}</span>
            <span className="tree-label" style={{ flex: 1 }}>
              {p.title || 'Untitled'}
            </span>
            <button
              className="tree-action"
              title="Restore"
              onClick={() => {
                void restore({ id: p._id as Id<'pages'> }).then(() => {
                  onNavigate(p._id);
                  showToast(`Restored “${p.title || 'Untitled'}”`);
                });
              }}
            >
              <RestoreGlyph size={13} />
            </button>
            <button
              className="tree-action"
              title="Delete forever"
              onClick={() => {
                if (window.confirm(`Permanently delete “${p.title || 'Untitled'}”? This cannot be undone.`)) {
                  void deleteForever({ id: p._id as Id<'pages'> });
                }
              }}
            >
              <TrashGlyph size={13} />
            </button>
          </div>
        ))}
        {items && items.length === 0 && <MenuNote>Trash is empty.</MenuNote>}
      </div>
      {items && items.length > 0 && (
        <>
          <MenuSep />
          <MenuItem
            icon={<TrashGlyph />}
            label="Empty Trash"
            danger
            onClick={() => {
              if (window.confirm('Permanently delete everything in Trash? This cannot be undone.')) {
                void emptyTrash({});
                showToast('Trash emptied');
              }
            }}
          />
        </>
      )}
    </Popover>
  );
}
