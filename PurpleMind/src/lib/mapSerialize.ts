import type { MindGraph } from './graph';

export const PURPLEMIND_DOC_FORMAT = 'purplemind.map';
export const PURPLEMIND_DOC_VERSION = 1;

export interface MapDoc {
  format: typeof PURPLEMIND_DOC_FORMAT;
  version: number;
  title: string;
  nodes: { id: string; label: string; x: number; y: number; color: string | null }[];
  edges: { id: string; source: string; target: string }[];
}

/** Serialize a map + its graph to the PurpleMind `.json` document format. */
export function serializeMap(title: string, graph: MindGraph): string {
  const doc: MapDoc = {
    format: PURPLEMIND_DOC_FORMAT,
    version: PURPLEMIND_DOC_VERSION,
    title,
    nodes: graph.nodes.map((n) => ({
      id: n.id,
      label: n.label,
      x: n.x,
      y: n.y,
      color: n.color ?? null,
    })),
    edges: graph.edges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
  };
  return JSON.stringify(doc, null, 2);
}

export interface ParsedMap {
  title: string;
  nodes: { id: string; label: string; x: number; y: number; color: string | null }[];
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
