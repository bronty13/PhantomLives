import type { MindGraph } from './graph';

export const PURPLEMIND_DOC_FORMAT = 'purplemind.map';
export const PURPLEMIND_DOC_VERSION = 2;

export interface DocNode {
  id: string;
  label: string;
  x: number;
  y: number;
  color: string | null;
  icon?: string | null;
  checked?: number | null;
  note?: string | null;
  collapsed?: number;
}

export interface MapDoc {
  format: typeof PURPLEMIND_DOC_FORMAT;
  version: number;
  title: string;
  nodes: DocNode[];
  edges: { id: string; source: string; target: string }[];
}

/** A node enriched with the optional item attributes, for serialization. */
export interface RichNode {
  id: string;
  label: string;
  x: number;
  y: number;
  color?: string | null;
  icon?: string | null;
  checked?: number | null;
  note?: string | null;
  collapsed?: number;
}

/** Serialize a map + its graph to the PurpleMind `.json` document format. */
export function serializeMap(
  title: string,
  graph: MindGraph,
  attrs?: Map<string, Partial<RichNode>>,
): string {
  const doc: MapDoc = {
    format: PURPLEMIND_DOC_FORMAT,
    version: PURPLEMIND_DOC_VERSION,
    title,
    nodes: graph.nodes.map((n) => {
      const a = attrs?.get(n.id);
      return {
        id: n.id,
        label: n.label,
        x: n.x,
        y: n.y,
        color: n.color ?? null,
        icon: a?.icon ?? null,
        checked: a?.checked ?? null,
        note: a?.note ?? null,
        collapsed: a?.collapsed ?? 0,
      };
    }),
    edges: graph.edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
  };
  return JSON.stringify(doc, null, 2);
}

export interface ParsedMap {
  title: string;
  nodes: {
    id: string;
    label: string;
    x: number;
    y: number;
    color: string | null;
    icon: string | null;
    checked: number | null;
    note: string | null;
    collapsed: number;
  }[];
  edges: { source: string; target: string }[];
}

/**
 * Parse + validate a PurpleMind map document. Edge endpoints that don't
 * resolve to a node are dropped. Throws on malformed input. Node ids are
 * returned as-is so the caller can remap them to fresh ids on import.
 */
export function parseMap(json: string): ParsedMap {
  let doc: unknown;
  try {
    doc = JSON.parse(json);
  } catch {
    throw new Error('Not valid JSON.');
  }
  if (typeof doc !== 'object' || doc === null) {
    throw new Error('Expected a PurpleMind map object.');
  }
  const d = doc as Partial<MapDoc>;
  if (d.format !== PURPLEMIND_DOC_FORMAT) {
    throw new Error('This file is not a PurpleMind map (missing format tag).');
  }
  if (!Array.isArray(d.nodes) || !Array.isArray(d.edges)) {
    throw new Error('Map document is missing nodes or edges.');
  }

  const nodes = d.nodes.map((n, i) => {
    if (typeof n?.id !== 'string') throw new Error(`Node ${i} has no id.`);
    return {
      id: n.id,
      label: typeof n.label === 'string' ? n.label : '',
      x: Number.isFinite(n.x) ? (n.x as number) : 0,
      y: Number.isFinite(n.y) ? (n.y as number) : 0,
      color: typeof n.color === 'string' ? n.color : null,
      icon: typeof n.icon === 'string' ? n.icon : null,
      checked: n.checked === 0 || n.checked === 1 ? n.checked : null,
      note: typeof n.note === 'string' ? n.note : null,
      collapsed: n.collapsed === 1 ? 1 : 0,
    };
  });

  const ids = new Set(nodes.map((n) => n.id));
  const edges = (d.edges as unknown[])
    .map((e) => e as { source?: unknown; target?: unknown })
    .filter(
      (e): e is { source: string; target: string } =>
        typeof e.source === 'string' &&
        typeof e.target === 'string' &&
        ids.has(e.source) &&
        ids.has(e.target),
    )
    .map((e) => ({ source: e.source, target: e.target }));

  return {
    title: typeof d.title === 'string' && d.title.trim() ? d.title : 'Imported map',
    nodes,
    edges,
  };
}
