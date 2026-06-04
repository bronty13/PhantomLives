import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Background,
  Controls,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  addEdge,
  useEdgesState,
  useNodesState,
  useReactFlow,
  type Connection,
  type Edge,
  type EdgeTypes,
  type Node,
  type NodeTypes,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { readTextFile } from '@tauri-apps/plugin-fs';

import { NodeCard, type MindNodeData } from '../components/NodeCard';
import { BranchEdge } from '../components/BranchEdge';
import { ExportMenu, type ExportFormat, type ImportKind } from '../components/ExportMenu';
import {
  listNodes,
  createNode,
  updateNodeLabel,
  updateNodeColor,
  updateNodePosition,
  updateNodePositions,
  deleteNode,
  setNodeChecked,
  setNodeNote,
  setNodeCollapsed,
  setNodeIcon,
} from '../data/nodes';
import { listEdges, createEdge, deleteEdge } from '../data/edges';
import { saveViewport, touchMap } from '../data/maps';
import { getExportDir } from '../data/appSettings';
import { layoutTree } from '../lib/autoLayout';
import { toMarkdown, fromMarkdown } from '../lib/markdownOutline';
import { serializeMap, parseMap, type RichNode } from '../lib/mapSerialize';
import { base64FromString } from '../lib/base64';
import { renderPng, renderSvg, renderPdf } from '../lib/exportImage';
import { importGraph } from '../data/importMap';
import { computeBranchStyles } from '../lib/branchStyle';
import { hiddenNodeIds } from '../lib/visibility';
import { buildForest, type MindGraph } from '../lib/graph';

const SWATCHES = [null, '#e0699b', '#f08a5d', '#f6b93b', '#46b98a', '#4f8df5', '#7c4ac4'];
const ICONS = ['💡', '📌', '✅', '⭐', '🔥', '❓', '⚠️', '🎯', '🚀', '❤️', '🧩', '📅', '🔗', '💬', '📁', '🧠'];

function stamp(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

/** Internal per-node data we keep in React Flow state (style is derived). */
interface BaseData extends Record<string, unknown> {
  label: string;
  colorOverride: string | null;
  icon: string | null;
  checked: number | null;
  note: string | null;
  collapsed: boolean;
  editEpoch: number;
}

interface EditorProps {
  mapId: string;
  title: string;
  onMapsChanged: (selectId?: string) => void;
}

function Editor({ mapId, title, onMapsChanged }: EditorProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  const [iconOpen, setIconOpen] = useState(false);
  const [noteEditor, setNoteEditor] = useState<{ id: string; value: string } | null>(null);
  const rf = useReactFlow();
  const wrapperRef = useRef<HTMLDivElement>(null);
  const vpTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const commitLabel = useCallback(
    (id: string, label: string) => {
      setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, data: { ...n.data, label } } : n)));
      void updateNodeLabel(id, label).then(() => touchMap(mapId));
    },
    [mapId, setNodes],
  );

  const toggleCollapse = useCallback(
    (id: string) => {
      let nextCollapsed = false;
      setNodes((ns) =>
        ns.map((n) => {
          if (n.id !== id) return n;
          nextCollapsed = !(n.data as BaseData).collapsed;
          return { ...n, data: { ...n.data, collapsed: nextCollapsed } };
        }),
      );
      void setNodeCollapsed(id, nextCollapsed).then(() => touchMap(mapId));
    },
    [mapId, setNodes],
  );

  const toggleCheck = useCallback(
    (id: string) => {
      let next: number | null = null;
      setNodes((ns) =>
        ns.map((n) => {
          if (n.id !== id) return n;
          const cur = (n.data as BaseData).checked;
          next = cur === 1 ? 0 : 1; // toggle done state (checkbox already present)
          return { ...n, data: { ...n.data, checked: next } };
        }),
      );
      void setNodeChecked(id, next).then(() => touchMap(mapId));
    },
    [mapId, setNodes],
  );

  const mkData = useCallback(
    (over: Partial<BaseData>): BaseData => ({
      label: '',
      colorOverride: null,
      icon: null,
      checked: null,
      note: null,
      collapsed: false,
      editEpoch: 0,
      ...over,
    }),
    [],
  );

  const nodeTypes = useMemo<NodeTypes>(() => ({ mind: NodeCard }), []);
  const edgeTypes = useMemo<EdgeTypes>(() => ({ branch: BranchEdge }), []);

  // Load the map's graph whenever the active map changes.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [nrows, erows] = await Promise.all([listNodes(mapId), listEdges(mapId)]);
      if (cancelled) return;
      setNodes(
        nrows.map((n) => ({
          id: n.id,
          type: 'mind',
          position: { x: n.x, y: n.y },
          data: mkData({
            label: n.label,
            colorOverride: n.color,
            icon: n.icon,
            checked: n.checked,
            note: n.note,
            collapsed: n.collapsed === 1,
          }),
        })),
      );
      setEdges(erows.map((e) => ({ id: e.id, source: e.source_id, target: e.target_id })));
      setTimeout(() => rf.fitView({ padding: 0.2, duration: 300 }), 60);
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapId, mkData]);

  // The full graph (structure + stored colour overrides), used for styling,
  // layout, export, and keyboard navigation.
  const graphSnapshot = useCallback(
    (): MindGraph => ({
      nodes: nodes.map((n) => ({
        id: n.id,
        label: (n.data as BaseData).label,
        x: n.position.x,
        y: n.position.y,
        color: (n.data as BaseData).colorOverride,
      })),
      edges: edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
    }),
    [nodes, edges],
  );

  // Derived branch styling + collapse visibility.
  const styles = useMemo(() => {
    const overrides = new Map(nodes.map((n) => [n.id, (n.data as BaseData).colorOverride]));
    return computeBranchStyles(
      {
        nodes: nodes.map((n) => ({ id: n.id, label: '', x: n.position.x, y: n.position.y })),
        edges: edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
      },
      overrides,
    );
  }, [nodes, edges]);

  const hidden = useMemo(() => {
    const collapsed = new Set(nodes.filter((n) => (n.data as BaseData).collapsed).map((n) => n.id));
    if (collapsed.size === 0) return new Set<string>();
    return hiddenNodeIds(
      {
        nodes: nodes.map((n) => ({ id: n.id, label: '', x: 0, y: 0 })),
        edges: edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
      },
      collapsed,
    );
  }, [nodes, edges]);

  // Nodes/edges actually handed to React Flow: visible only, with derived
  // style merged into each node's data and branch colour onto each edge.
  const displayNodes = useMemo(
    () =>
      nodes
        .filter((n) => !hidden.has(n.id))
        .map((n) => {
          const st = styles.get(n.id);
          const base = n.data as BaseData;
          const data: MindNodeData = {
            label: base.label,
            color: st?.color ?? '#9361db',
            tier: st?.tier ?? 'topic',
            icon: base.icon,
            checked: base.checked,
            hasNote: !!base.note,
            childCount: st?.childCount ?? 0,
            collapsed: base.collapsed,
            editEpoch: base.editEpoch,
            onCommitLabel: commitLabel,
            onToggleCollapse: toggleCollapse,
            onToggleCheck: toggleCheck,
          };
          return { ...n, data };
        }),
    [nodes, hidden, styles, commitLabel, toggleCollapse, toggleCheck],
  );

  const displayEdges = useMemo(
    () =>
      edges
        .filter((e) => !hidden.has(e.source) && !hidden.has(e.target))
        .map((e) => {
          const childStyle = styles.get(e.target);
          return {
            ...e,
            type: 'branch',
            data: { color: childStyle?.branchColor ?? '#9361db', depth: childStyle?.depth ?? 1 },
          };
        }),
    [edges, hidden, styles],
  );

  const onConnect = useCallback(
    (c: Connection) => {
      void (async () => {
        const row = await createEdge(mapId, c.source!, c.target!);
        if (row) {
          setEdges((es) => addEdge({ id: row.id, source: row.source_id, target: row.target_id }, es));
          await touchMap(mapId);
        }
      })();
    },
    [mapId, setEdges],
  );

  const onNodeDragStop = useCallback(
    (_e: unknown, node: Node) => {
      void updateNodePosition(node.id, node.position.x, node.position.y).then(() => touchMap(mapId));
    },
    [mapId],
  );

  const onNodesDelete = useCallback(
    (deleted: Node[]) => {
      void Promise.all(deleted.map((n) => deleteNode(n.id))).then(() => {
        touchMap(mapId);
        const gone = new Set(deleted.map((n) => n.id));
        setEdges((es) => es.filter((e) => !gone.has(e.source) && !gone.has(e.target)));
      });
    },
    [mapId, setEdges],
  );

  const onEdgesDelete = useCallback(
    (deleted: Edge[]) => {
      void Promise.all(deleted.map((e) => deleteEdge(e.id))).then(() => touchMap(mapId));
    },
    [mapId],
  );

  const persistViewport = useCallback(() => {
    if (vpTimer.current) clearTimeout(vpTimer.current);
    vpTimer.current = setTimeout(() => void saveViewport(mapId, rf.getViewport()), 400);
  }, [mapId, rf]);

  const addNodeAt = useCallback(
    async (flowX: number, flowY: number, label = 'New idea') => {
      const row = await createNode(mapId, label, flowX, flowY);
      setNodes((ns) => [
        ...ns.map((n) => (n.selected ? { ...n, selected: false } : n)),
        {
          id: row.id,
          type: 'mind',
          position: { x: row.x, y: row.y },
          selected: true,
          data: mkData({ label: row.label, colorOverride: row.color }),
        },
      ]);
      await touchMap(mapId);
      return row.id;
    },
    [mapId, mkData, setNodes],
  );

  const addNodeCentre = useCallback(() => {
    const rect = wrapperRef.current?.getBoundingClientRect();
    const screen = rect
      ? { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
      : { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const pos = rf.screenToFlowPosition(screen);
    void addNodeAt(pos.x, pos.y);
  }, [rf, addNodeAt]);

  // Add a child of `parentId` (defaults to the selected node).
  const addChildOf = useCallback(
    async (parentId: string) => {
      const parent = nodes.find((n) => n.id === parentId);
      if (!parent) return;
      const siblingCount = edges.filter((e) => e.source === parentId).length;
      const childId = await addNodeAt(
        parent.position.x + 240,
        parent.position.y + siblingCount * 96,
        'New idea',
      );
      const edge = await createEdge(mapId, parentId, childId);
      if (edge) setEdges((es) => addEdge({ id: edge.id, source: edge.source_id, target: edge.target_id }, es));
      return childId;
    },
    [nodes, edges, addNodeAt, mapId, setEdges],
  );

  const addChild = useCallback(() => {
    const sel = nodes.find((n) => n.selected);
    if (sel) void addChildOf(sel.id);
  }, [nodes, addChildOf]);

  const applyColor = useCallback(
    (color: string | null) => {
      const ids = nodes.filter((n) => n.selected).map((n) => n.id);
      if (ids.length === 0) return;
      setNodes((ns) => ns.map((n) => (n.selected ? { ...n, data: { ...n.data, colorOverride: color } } : n)));
      void Promise.all(ids.map((id) => updateNodeColor(id, color))).then(() => touchMap(mapId));
    },
    [nodes, mapId, setNodes],
  );

  const applyIcon = useCallback(
    (icon: string | null) => {
      const ids = nodes.filter((n) => n.selected).map((n) => n.id);
      if (ids.length === 0) return;
      setNodes((ns) => ns.map((n) => (n.selected ? { ...n, data: { ...n.data, icon } } : n)));
      void Promise.all(ids.map((id) => setNodeIcon(id, icon))).then(() => touchMap(mapId));
      setIconOpen(false);
    },
    [nodes, mapId, setNodes],
  );

  // Toolbar checkbox toggles the *presence* of a checkbox on the selection.
  const toggleCheckboxPresence = useCallback(() => {
    const selected = nodes.filter((n) => n.selected);
    if (selected.length === 0) return;
    const add = selected.some((n) => (n.data as BaseData).checked === null);
    const next = add ? 0 : null;
    const ids = selected.map((n) => n.id);
    setNodes((ns) => ns.map((n) => (n.selected ? { ...n, data: { ...n.data, checked: next } } : n)));
    void Promise.all(ids.map((id) => setNodeChecked(id, next))).then(() => touchMap(mapId));
  }, [nodes, mapId, setNodes]);

  const openNoteEditor = useCallback(() => {
    const sel = nodes.find((n) => n.selected);
    if (!sel) return;
    setNoteEditor({ id: sel.id, value: (sel.data as BaseData).note ?? '' });
  }, [nodes]);

  const saveNote = useCallback(() => {
    if (!noteEditor) return;
    const { id, value } = noteEditor;
    const note = value.trim() ? value : null;
    setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, data: { ...n.data, note } } : n)));
    void setNodeNote(id, note).then(() => touchMap(mapId));
    setNoteEditor(null);
  }, [noteEditor, mapId, setNodes]);

  // Lay out only the currently-visible subgraph.
  const tidy = useCallback(() => {
    const full = graphSnapshot();
    const visible: MindGraph = {
      nodes: full.nodes.filter((n) => !hidden.has(n.id)),
      edges: full.edges.filter((e) => !hidden.has(e.source) && !hidden.has(e.target)),
    };
    const positions = layoutTree(visible);
    const byId = new Map(positions.map((p) => [p.id, p]));
    setNodes((ns) => ns.map((n) => {
      const p = byId.get(n.id);
      return p ? { ...n, position: { x: p.x, y: p.y } } : n;
    }));
    void updateNodePositions(positions).then(() => touchMap(mapId));
    setTimeout(() => rf.fitView({ padding: 0.2, duration: 400 }), 50);
  }, [graphSnapshot, hidden, setNodes, mapId, rf]);

  const beginEdit = useCallback(
    (id: string) => {
      setNodes((ns) =>
        ns.map((n) =>
          n.id === id ? { ...n, data: { ...n.data, editEpoch: ((n.data as BaseData).editEpoch ?? 0) + 1 } } : n,
        ),
      );
    },
    [setNodes],
  );

  const selectOnly = useCallback(
    (id: string) => {
      setNodes((ns) => ns.map((n) => ({ ...n, selected: n.id === id })));
      const target = nodes.find((n) => n.id === id);
      if (target) rf.setCenter(target.position.x, target.position.y, { zoom: rf.getZoom(), duration: 200 });
    },
    [nodes, rf, setNodes],
  );

  // ---- Keyboard-tree editing -------------------------------------------------
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (document.activeElement?.tagName ?? '').toLowerCase();
      if (tag === 'textarea' || tag === 'input' || (document.activeElement as HTMLElement)?.isContentEditable) {
        return; // let inline editing / fields handle keys
      }
      const sel = nodes.find((n) => n.selected);
      if (!sel) return;
      const graph = graphSnapshot();
      const { parent, children } = buildForest(graph);

      if (e.key === 'Tab') {
        e.preventDefault();
        void addChildOf(sel.id);
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const p = parent.get(sel.id) ?? null;
        void addChildOf(p ?? sel.id); // sibling = child of parent; root → child
      } else if (e.key === ' ' || e.key === 'Spacebar') {
        e.preventDefault();
        beginEdit(sel.id);
      } else if (e.key === 'ArrowLeft') {
        const p = parent.get(sel.id);
        if (p) {
          e.preventDefault();
          selectOnly(p);
        }
      } else if (e.key === 'ArrowRight') {
        const kids = (children.get(sel.id) ?? []).filter((c) => !hidden.has(c));
        if (kids.length) {
          e.preventDefault();
          selectOnly(kids[0]);
        }
      } else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        const p = parent.get(sel.id);
        const sibs = p ? children.get(p) ?? [] : [];
        const idx = sibs.indexOf(sel.id);
        if (idx >= 0) {
          const next = e.key === 'ArrowUp' ? sibs[idx - 1] : sibs[idx + 1];
          if (next) {
            e.preventDefault();
            selectOnly(next);
          }
        }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [nodes, hidden, graphSnapshot, addChildOf, beginEdit, selectOnly]);

  // ---- Export / import -------------------------------------------------------
  const attrsMap = useCallback(
    (): Map<string, Partial<RichNode>> =>
      new Map(
        nodes.map((n) => {
          const b = n.data as BaseData;
          return [n.id, { icon: b.icon, checked: b.checked, note: b.note, collapsed: b.collapsed ? 1 : 0 }];
        }),
      ),
    [nodes],
  );

  const onExport = useCallback(
    (format: ExportFormat) => {
      void (async () => {
        setBusy(true);
        setStatus('Exporting…');
        try {
          const dirOverride = (await getExportDir()) || null;
          let base64: string;
          let ext: string;
          if (format === 'png') {
            base64 = (await renderPng(displayNodes)).base64;
            ext = 'png';
          } else if (format === 'svg') {
            base64 = (await renderSvg(displayNodes)).base64;
            ext = 'svg';
          } else if (format === 'pdf') {
            base64 = (await renderPdf(displayNodes)).base64;
            ext = 'pdf';
          } else if (format === 'json') {
            base64 = base64FromString(serializeMap(title, graphSnapshot(), attrsMap()));
            ext = 'json';
          } else {
            const checkedOf = new Map(nodes.map((n) => [n.id, (n.data as BaseData).checked]));
            base64 = base64FromString(toMarkdown(graphSnapshot(), checkedOf));
            ext = 'md';
          }
          const filename = `${title}_${stamp()}.${ext}`;
          const res = await invoke<{ outputPath: string }>('save_export', {
            filename,
            contentBase64: base64,
            dirOverride,
          });
          setStatus(`Saved to ${res.outputPath}`);
          void invoke('reveal_path', { path: res.outputPath }).catch(() => {});
        } catch (e) {
          setStatus(`Export failed: ${e}`);
        } finally {
          setBusy(false);
        }
      })();
    },
    [displayNodes, nodes, title, graphSnapshot, attrsMap],
  );

  const onImport = useCallback(
    (kind: ImportKind) => {
      void (async () => {
        const filters =
          kind === 'json'
            ? [{ name: 'PurpleMind map', extensions: ['json'] }]
            : [{ name: 'Markdown outline', extensions: ['md', 'markdown', 'txt'] }];
        const picked = await open({ multiple: false, filters });
        if (!picked || typeof picked !== 'string') return;
        setBusy(true);
        setStatus('Importing…');
        try {
          const text = await readTextFile(picked);
          let newId: string;
          if (kind === 'json') {
            const parsed = parseMap(text);
            const hasPositions = parsed.nodes.some((n) => n.x !== 0 || n.y !== 0);
            newId = await importGraph(
              parsed.title,
              parsed.nodes.map((n) => ({
                ref: n.id,
                label: n.label,
                x: n.x,
                y: n.y,
                color: n.color,
                icon: n.icon,
                checked: n.checked,
                note: n.note,
              })),
              parsed.edges,
              !hasPositions,
            );
          } else {
            const parsed = fromMarkdown(text);
            const name = picked.split(/[\\/]/).pop()?.replace(/\.[^.]+$/, '') || 'Imported outline';
            newId = await importGraph(
              name,
              parsed.nodes.map((n) => ({ ref: n.tempId, label: n.label, checked: n.checked })),
              parsed.edges,
              true,
            );
          }
          setStatus('Imported! Opening new map…');
          onMapsChanged(newId);
        } catch (e) {
          setStatus(`Import failed: ${e}`);
        } finally {
          setBusy(false);
        }
      })();
    },
    [onMapsChanged],
  );

  const anySelected = nodes.some((n) => n.selected);

  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-wrap items-center gap-1.5 border-b border-surface-border bg-surface-card px-4 py-2.5">
        <h1 className="mr-2 max-w-[24ch] truncate font-display text-lg text-brand-600" title={title}>
          {title}
        </h1>
        <button type="button" className="btn-soft" onClick={addNodeCentre}>＋ Node</button>
        <button type="button" className="btn-soft" onClick={addChild} disabled={!anySelected}>＋ Child</button>
        <button type="button" className="btn-soft" onClick={tidy}>✨ Tidy</button>
        <button type="button" className="btn-soft" onClick={() => rf.fitView({ padding: 0.2, duration: 300 })}>⤢ Fit</button>

        <span className="mx-1 h-5 w-px bg-surface-border" />

        <button type="button" className="btn-soft" onClick={toggleCheckboxPresence} disabled={!anySelected} title="Toggle checkbox on selection">☑</button>
        <button type="button" className="btn-soft" onClick={openNoteEditor} disabled={!anySelected} title="Edit note">📝</button>
        <div className="relative">
          <button type="button" className="btn-soft" onClick={() => setIconOpen((o) => !o)} disabled={!anySelected} title="Set icon">😀</button>
          {iconOpen && (
            <div className="absolute z-20 mt-1 grid w-56 grid-cols-8 gap-1 card p-2 shadow-cute">
              {ICONS.map((ic) => (
                <button key={ic} type="button" className="rounded-lg p-1 text-lg hover:bg-surface-input" onClick={() => applyIcon(ic)}>{ic}</button>
              ))}
              <button type="button" className="col-span-8 mt-1 rounded-lg px-2 py-1 text-xs hover:bg-surface-input" onClick={() => applyIcon(null)}>Clear icon</button>
            </div>
          )}
        </div>

        <div className="flex items-center gap-1 pl-1" title={anySelected ? 'Colour selected (a top-level branch recolours its whole subtree)' : 'Select a node to colour it'}>
          {SWATCHES.map((c, i) => (
            <button
              key={i}
              type="button"
              disabled={!anySelected}
              onClick={() => applyColor(c)}
              className="h-5 w-5 rounded-full border border-surface-border disabled:opacity-40"
              style={{ background: c ?? 'rgb(var(--surface-input))' }}
              title={c ?? 'Auto (branch colour)'}
            >
              {c === null ? '∅' : ''}
            </button>
          ))}
        </div>

        <div className="ml-auto">
          <ExportMenu busy={busy} onExport={onExport} onImport={onImport} />
        </div>
      </div>

      {status && (
        <div className="truncate border-b border-surface-border bg-surface-base px-4 py-1 text-xs text-surface-muted">{status}</div>
      )}

      <div className="relative flex-1" ref={wrapperRef}>
        <ReactFlow
          nodes={displayNodes}
          edges={displayEdges}
          nodeTypes={nodeTypes}
          edgeTypes={edgeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeDragStop={onNodeDragStop}
          onNodesDelete={onNodesDelete}
          onEdgesDelete={onEdgesDelete}
          onMoveEnd={persistViewport}
          onPaneClick={() => setStatus('')}
          onDoubleClick={(e) => {
            if ((e.target as HTMLElement).classList.contains('react-flow__pane')) {
              const pos = rf.screenToFlowPosition({ x: e.clientX, y: e.clientY });
              void addNodeAt(pos.x, pos.y);
            }
          }}
          fitView
          deleteKeyCode={['Backspace', 'Delete']}
          proOptions={{ hideAttribution: true }}
        >
          <Background color="rgb(var(--surface-border))" gap={24} />
          <Controls />
          <MiniMap
            pannable
            zoomable
            nodeColor={(n) => ((n.data as MindNodeData)?.color ?? 'rgb(147 97 219)') as string}
            nodeStrokeColor="transparent"
          />
        </ReactFlow>

        {noteEditor && (
          <div className="absolute right-4 top-4 z-30 w-72 card p-3 shadow-cute">
            <div className="mb-2 text-sm font-semibold">Note</div>
            <textarea
              autoFocus
              className="field h-32 resize-none"
              value={noteEditor.value}
              onChange={(e) => setNoteEditor({ ...noteEditor, value: e.target.value })}
            />
            <div className="mt-2 flex justify-end gap-2">
              <button type="button" className="btn-ghost" onClick={() => setNoteEditor(null)}>Cancel</button>
              <button type="button" className="btn-primary" onClick={saveNote}>Save</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export function MapEditorView(props: EditorProps) {
  return (
    <ReactFlowProvider>
      <Editor {...props} />
    </ReactFlowProvider>
  );
}
