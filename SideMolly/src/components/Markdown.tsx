// Shared markdown renderer. Wraps the markdownLite parser into React
// elements — used by the DocDrawer (info.md previews) and the in-app
// Manual (USER_MANUAL.md). Headings get slug ids so a table of contents
// can anchor-scroll to them.

import { parseMarkdownLite, type MdBlock, type MdInline } from '../lib/markdownLite';

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function inlineText(items: MdInline[]): string {
  return items.map((i) => i.text).join('');
}

export interface TocHeading { level: 1 | 2 | 3; text: string; id: string }

/** Pull headings (for a table of contents) out of parsed blocks. */
export function headingsOf(blocks: MdBlock[]): TocHeading[] {
  const out: TocHeading[] = [];
  for (const b of blocks) {
    if (b.kind === 'heading') {
      const text = inlineText(b.inline);
      out.push({ level: b.level, text, id: slugify(text) });
    }
  }
  return out;
}

/** Render a markdown source string. */
export function Markdown({ source, className }: { source: string; className?: string }) {
  return <MarkdownBlocks blocks={parseMarkdownLite(source)} className={className} />;
}

/** Render already-parsed blocks (callers that also need the TOC parse once). */
export function MarkdownBlocks({ blocks, className }: { blocks: MdBlock[]; className?: string }) {
  return (
    <div className={className ?? 'flex flex-col gap-3 text-sm'}>
      {blocks.map((b, i) => <BlockEl key={i} b={b} />)}
    </div>
  );
}

function BlockEl({ b }: { b: MdBlock }) {
  switch (b.kind) {
    case 'heading': {
      const id = slugify(inlineText(b.inline));
      const cls =
        b.level === 1 ? 'display-font text-2xl mt-2' :
        b.level === 2 ? 'display-font text-xl mt-2' :
        'display-font text-base mt-1 font-semibold';
      return (
        <div id={id} className={cls} style={{ color: 'rgb(var(--surface-accent))', scrollMarginTop: 24 }}>
          <InlineEl items={b.inline} />
        </div>
      );
    }
    case 'paragraph': return <p className="text-sm leading-relaxed"><InlineEl items={b.inline} /></p>;
    case 'rule': return <hr style={{ borderColor: 'rgb(var(--surface-border))' }} />;
    case 'quote': return (
      <blockquote className="text-sm pl-3" style={{
        borderLeft: '3px solid rgb(var(--surface-accent) / 0.4)',
        color: 'rgb(var(--surface-muted))',
      }}><InlineEl items={b.inline} /></blockquote>
    );
    case 'codeblock': return (
      <pre className="font-mono text-xs whitespace-pre-wrap sm-card"
           style={{ background: 'rgb(var(--surface-base))' }}>{b.text}</pre>
    );
    case 'list': {
      if (b.ordered) return (
        <ol className="list-decimal list-inside text-sm flex flex-col gap-0.5">
          {b.items.map((it, i) => <li key={i}><InlineEl items={it} /></li>)}
        </ol>
      );
      return (
        <ul className="list-disc list-inside text-sm flex flex-col gap-0.5">
          {b.items.map((it, i) => <li key={i}><InlineEl items={it} /></li>)}
        </ul>
      );
    }
  }
}

function InlineEl({ items }: { items: MdInline[] }) {
  return (
    <>
      {items.map((it, i) => {
        switch (it.kind) {
          case 'text':   return <span key={i}>{it.text}</span>;
          case 'code':   return (
            <code key={i} className="font-mono text-[0.85em] px-1 py-0.5 rounded"
                  style={{ background: 'rgb(var(--surface-base))' }}>{it.text}</code>
          );
          case 'bold':   return <strong key={i}>{it.text}</strong>;
          case 'italic': return <em key={i}>{it.text}</em>;
          case 'link':   return (
            <a key={i} href={it.url} target="_blank" rel="noreferrer" className="underline"
               style={{ color: 'rgb(var(--surface-accent))' }}>{it.text}</a>
          );
        }
      })}
    </>
  );
}
