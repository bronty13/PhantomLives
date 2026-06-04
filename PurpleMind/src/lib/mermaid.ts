import { buildForest, type MindGraph } from './graph';

// Characters that break Mermaid mindmap node text; stripped for safety.
function escLabel(s: string): string {
  const cleaned = (s || '')
    .replace(/\r?\n/g, ' ')
    .replace(/[()[\]{}:"<>]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned || 'Untitled';
}

/**
 * Render the map as a **Mermaid `mindmap` diagram** — a Markdown code block
 * that renders as an actual radial mindmap in GitHub, Obsidian, VS Code, etc.
 * The single root is drawn as a circle; descendants are indented beneath it.
 * If the graph has several roots, a synthetic root (the map title) ties them
 * together (Mermaid mindmaps allow only one root). Pure + deterministic.
 */
export function toMermaidMindmap(title: string, graph: MindGraph): string {
  const { roots, children } = buildForest(graph);
  const labelOf = new Map(graph.nodes.map((n) => [n.id, n.label]));
  const lines: string[] = ['mindmap'];

  const emit = (id: string, depth: number) => {
    lines.push(`${'  '.repeat(depth + 1)}${escLabel(labelOf.get(id) ?? '')}`);
    for (const k of children.get(id) ?? []) emit(k, depth + 1);
  };

  if (roots.length === 1) {
    lines.push(`  rootNode((${escLabel(labelOf.get(roots[0]) ?? title)}))`);
    for (const k of children.get(roots[0]) ?? []) emit(k, 1);
  } else {
    lines.push(`  rootNode((${escLabel(title)}))`);
    for (const r of roots) emit(r, 1);
  }

  return lines.join('\n') + '\n';
}

/** Wrap the Mermaid diagram in a Markdown document with a heading + fence. */
export function toMermaidMarkdownDoc(title: string, graph: MindGraph): string {
  const heading = escLabel(title) === 'Untitled' ? 'Mind map' : title.replace(/\r?\n/g, ' ').trim();
  return `# ${heading}\n\n\`\`\`mermaid\n${toMermaidMindmap(title, graph)}\`\`\`\n`;
}
