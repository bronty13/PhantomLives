import { buildForest, type MindGraph } from './graph';

const INDENT = '  '; // two spaces per level

/**
 * Render a mind map as an indented Markdown bullet outline. The graph is
 * reduced to a spanning forest (see buildForest) so each node appears exactly
 * once; cross-links beyond the tree are not represented in the outline.
 */
export function toMarkdown(graph: MindGraph): string {
  const { roots, children } = buildForest(graph);
  const labelOf = new Map(graph.nodes.map((n) => [n.id, n.label]));
  const lines: string[] = [];

  const walk = (id: string, depth: number) => {
    const label = (labelOf.get(id) ?? '').replace(/\r?\n/g, ' ').trim();
    lines.push(`${INDENT.repeat(depth)}- ${label}`);
    for (const k of children.get(id) ?? []) walk(k, depth + 1);
  };
  for (const r of roots) walk(r, 0);

  return lines.join('\n') + (lines.length ? '\n' : '');
}

export interface ParsedOutline {
  nodes: { tempId: string; label: string }[];
  edges: { source: string; target: string }[];
}

/**
 * Parse an indented bullet outline back into a node/edge structure with
 * temporary ids (`t0`, `t1`, …). Indentation is measured in leading spaces;
 * tabs count as two spaces. Bullets may start with `-`, `*`, or `+`. The
 * caller assigns real ids and runs auto-layout for positions.
 */
export function fromMarkdown(text: string): ParsedOutline {
  const nodes: { tempId: string; label: string }[] = [];
  const edges: { source: string; target: string }[] = [];
  // Stack of {indent, id} tracking the current ancestor chain.
  const stack: { indent: number; id: string }[] = [];
  let counter = 0;

  for (const raw of text.split(/\r?\n/)) {
    if (raw.trim() === '') continue;
    const expanded = raw.replace(/\t/g, '  ');
    const match = expanded.match(/^(\s*)(?:[-*+]\s+)?(.*)$/);
    if (!match) continue;
    const indent = match[1].length;
    const label = match[2].trim();
    if (label === '') continue;

    const tempId = `t${counter++}`;
    nodes.push({ tempId, label });

    // Pop ancestors at the same or deeper indent.
    while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
    const parent = stack[stack.length - 1];
    if (parent) edges.push({ source: parent.id, target: tempId });
    stack.push({ indent, id: tempId });
  }

  return { nodes, edges };
}
