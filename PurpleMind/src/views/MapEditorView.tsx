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
  type Node,
  type NodeTypes,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { readTextFile } from '@tauri-apps/plugin-fs';

import { NodeCard, type MindNodeData } from '../components/NodeCard';
import { ExportMenu, type ExportFormat, type ImportKind } from '../components/ExportMenu';
import { listNodes, createNode, updateNodeLabel, updateNodeColor, updateNodePosition, updateNodePositions, deleteNode } from '../data/nodes';
import { listEdges, createEdge, deleteEdge } from '../data/edges';
import { saveViewport, touchMap } from '../data/maps';
import { getExportDir } from '../data/appSettings';
import { layoutTree } from '../lib/autoLayout';
import { toMarkdown, fromMarkdown } from '../lib/markdownOutline';
import { serializeMap, parseMap } from '../lib/mapSerialize';
import { base64FromString } from '../lib/base64';
import { renderPng, renderSvg, renderPdf } from '../lib/exportImage';
import { importGraph } from '../data/importMap';
import type { MindGraph } from '../lib/graph';

const SWATCHES = [null, '#9361db', '#e0699b', '#f59e42', '#46b98a', '#4f8df5'];

function stamp(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
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
  const rf = useReactFlow();
  const wrapperRef = useRef<HTMLDivElement>(null);
  const vpTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const commitLabel = useCallback(
    (id: string, label: string) => {
      setNodes((ns) =>
        ns.map((n) => (n.id === id ? { ...n, data: { ...n.data, label } } : n)),
      );
      void updateNodeLabel(id, label).then(() => touchMap(mapId));
    },
    [mapId, setNodes],
  );

  const nodeTypes = useMemo<NodeTypes>(() => ({ mind: NodeCard }), []);

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
          data: { label: n.label, color: n.color, onCommitLabel: commitLabel } as MindNodeData,
        })),
      );
      setEdges(erows.map((e) => ({ id: e.id, source: e.source_id, target: e.target_id })));
      // Fit after the nodes paint.
      setTimeout(() => rf.fitView({ padding: 0.2, duration: 300 }), 60);
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapId, commitLabel]);

  const graphSnapshot = useCallback((): MindGraph => ({
    nodes: nodes.map((n) => ({
      id: n.id,
      label: (n.data as MindNodeData).label,
      x: n.position.x,
      y: n.position.y,
      color: (n.data as MindNodeData).color,
    })),
    edges: edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
  }), [nodes, edges]);

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
      void updateNodePosition(node.id, node.position.x, node.position.y).then(() =>
        touchMap(mapId),
      );
    },
    [mapId],
  );

  const onNodesDelete = useCallback(
    (deleted: Node[]) => {
      void Promise.all(deleted.map((n) => deleteNode(n.id))).then(() => {
        touchMap(mapId);
        // Edges touching deleted nodes are removed by React Flow + DB cascade;
        // reflect the cascade in local edge state.
        const goneIds = new Set(deleted.map((n) => n.id));
        setEdges((es) => es.filter((e) => !goneIds.has(e.source) && !goneIds.has(e.target)));
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
    vpTimer.current = setTimeout(() => {
      const vp = rf.getViewport();
      void saveViewport(mapId, vp);
    }, 400);
  }, [mapId, rf]);

  const addNodeAt = useCallback(
    async (flowX: number, flowY: number, label = 'New idea') => {
      const row = await createNode(mapId, label, flowX, flowY);
      // Select the new node (and deselect the rest) so the next `＋ Child`
      // nests *under it* — this is what lets you build arbitrarily deep
      // levels: node → child → grandchild → … just by clicking ＋ Child.
      setNodes((ns) => [
        ...ns.map((n) => (n.selected ? { ...n, selected: false } : n)),
        {
          id: row.id,
          type: 'mind',
          position: { x: row.x, y: row.y },
          selected: true,
          data: { label: row.label, color: row.color, onCommitLabel: commitLabel } as MindNodeData,
        },
      ]);
      await touchMap(mapId);
      return row.id;
    },
    [mapId, commitLabel, setNodes],
  );

  // Add a node at the centre of the current viewport.
  const addNodeCentre = useCallback(() => {
    const rect = wrapperRef.current?.getBoundingClientRect();
    const screen = rect
      ? { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
      : { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const pos = rf.screenToFlowPosition(screen);
    void addNodeAt(pos.x, pos.y);
  }, [rf, addNodeAt]);

  // Add a child connected to the (single) selected node. Siblings are
  // staggered vertically by how many children the parent already has so they
  // don't land exactly on top of each other (`✨ Tidy` re-flows them cleanly).
  const addChild = useCallback(() => {
    const selected = nodes.find((n) => n.selected);
    if (!selected) return;
    const siblingCount = edges.filter((e) => e.source === selected.id).length;
    const childY = selected.position.y + siblingCount * 96;
    void (async () => {
      const childId = await addNodeAt(selected.position.x + 240, childY, 'New idea');
      const edge = await createEdge(mapId, selected.id, childId);
      if (edge) setEdges((es) => addEdge({ id: edge.id, source: edge.source_id, target: edge.target_id }, es));
    })();
  }, [nodes, edges, addNodeAt, mapId, setEdges]);

  const applyColor = useCallback(
    (color: string | null) => {
      const selectedIds = nodes.filter((n) => n.selected).map((n) => n.id);
      if (selectedIds.length === 0) return;
      setNodes((ns) =>
        ns.map((n) => (n.selected ? { ...n, data: { ...n.data, color } } : n)),
      );
      void Promise.all(selectedIds.map((id) => updateNodeColor(id, color))).then(() =>
        touchMap(mapId),
      );
    },
    [nodes, mapId, setNodes],
  );

  const tidy = useCallback(() => {
    const positions = layoutTree(graphSnapshot());
    const byId = new Map(positions.map((p) => [p.id, p]));
    setNodes((ns) =>
      ns.map((n) => {
        const p = byId.get(n.id);
        return p ? { ...n, position: { x: p.x, y: p.y } } : n;
      }),
    );
    void updateNodePositions(positions).then(() => touchMap(mapId));
    setTimeout(() => rf.fitView({ padding: 0.2, duration: 400 }), 50);
  }, [graphSnapshot, setNodes, mapId, rf]);

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
            base64 = (await renderPng(nodes)).base64;
            ext = 'png';
          } else if (format === 'svg') {
            base64 = (await renderSvg(nodes)).base64;
            ext = 'svg';
          } else if (format === 'pdf') {
            base64 = (await renderPdf(nodes)).base64;
            ext = 'pdf';
          } else if (format === 'json') {
            base64 = base64FromString(serializeMap(title, graphSnapshot()));
            ext = 'json';
          } else {
            base64 = base64FromString(toMarkdown(graphSnapshot()));
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
    [nodes, title, graphSnapshot],
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
              parsed.nodes.map((n) => ({ ref: n.id, label: n.label, x: n.x, y: n.y, color: n.color })),
              parsed.edges,
              !hasPositions,
            );
          } else {
            const parsed = fromMarkdown(text);
            const name = picked.split(/[\\/]/).pop()?.replace(/\.[^.]+$/, '') || 'Imported outline';
            newId = await importGraph(
              name,
              parsed.nodes.map((n) => ({ ref: n.tempId, label: n.label })),
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
      <div className="flex flex-wrap items-center gap-2 border-b border-surface-border bg-surface-card px-4 py-2.5">
        <h1 className="mr-2 max-w-[28ch] truncate font-display text-lg text-brand-600" title={title}>
          {title}
        </h1>
        <button type="button" className="btn-soft" onClick={addNodeCentre}>
          ＋ Node
        </button>
        <button type="button" className="btn-soft" onClick={addChild} disabled={!anySelected}>
          ＋ Child
        </button>
        <button type="button" className="btn-soft" onClick={tidy}>
          ✨ Tidy
        </button>
        <button type="button" className="btn-soft" onClick={() => rf.fitView({ padding: 0.2, duration: 300 })}>
          ⤢ Fit
        </button>

        <div className="flex items-center gap-1 pl-1" title={anySelected ? 'Colour selected nodes' : 'Select a node to colour it'}>
          {SWATCHES.map((c, i) => (
            <button
              key={i}
              type="button"
              disabled={!anySelected}
              onClick={() => applyColor(c)}
              className="h-5 w-5 rounded-full border border-surface-border disabled:opacity-40"
              style={{ background: c ?? 'rgb(var(--surface-input))' }}
              title={c ?? 'Default'}
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
        <div className="truncate border-b border-surface-border bg-surface-base px-4 py-1 text-xs text-surface-muted">
          {status}
        </div>
      )}

      <div className="relative flex-1" ref={wrapperRef}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeDragStop={onNodeDragStop}
          onNodesDelete={onNodesDelete}
          onEdgesDelete={onEdgesDelete}
          onMoveEnd={persistViewport}
          onPaneClick={() => setStatus('')}
          onDoubleClick={(e) => {
            // Double-click empty canvas to drop a node there.
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
