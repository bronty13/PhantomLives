import { useEffect, useMemo, useRef, useState } from 'react';
// Vite inlines the file as a string literal at build time. Manual lives
// at repo root; the relative path crosses out of `src/` which Vite
// happily allows for static assets.
import manualText from '../../../USER_MANUAL.md?raw';
import {
  parseMarkdown,
  renderInline,
  type MdBlock,
  type InlineToken,
} from '../../lib/markdownLite';
import { SayingsBanner } from '../../components/SayingsBanner';

const HEADING_FONT_STACK = '"Comfortaa", "Quicksand", system-ui, sans-serif';

function InlineRender({ text }: { text: string }) {
  const tokens = useMemo<InlineToken[]>(() => renderInline(text), [text]);
  return (
    <>
      {tokens.map((tok, i) => {
        switch (tok.kind) {
          case 'text':    return <span key={i}>{tok.text}</span>;
          case 'bold':    return <strong key={i}>{tok.text}</strong>;
          case 'italic':  return <em key={i}>{tok.text}</em>;
          case 'strike':  return <span key={i} style={{ textDecoration: 'line-through', opacity: 0.6 }}>{tok.text}</span>;
          case 'code':
            return (
              <code
                key={i}
                className="font-mono text-[0.92em] px-1 py-0.5 rounded"
                style={{
                  background: 'rgb(var(--persona-tint))',
                  border: '1px solid rgb(var(--persona-primary) / 0.35)',
                }}
              >
                {tok.text}
              </code>
            );
          case 'link':
            return (
              <a
                key={i}
                href={tok.href}
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: 'rgb(var(--persona-accent))', textDecoration: 'underline' }}
              >
                {tok.text}
              </a>
            );
        }
      })}
    </>
  );
}

function BlockRender({ block }: { block: MdBlock }) {
  switch (block.kind) {
    case 'h1':
      return (
        <h1
          className="display-font font-bold mt-6 mb-3 persona-accent"
          style={{ fontFamily: HEADING_FONT_STACK, fontSize: '2rem', lineHeight: 1.15 }}
        >
          <InlineRender text={block.text} />
        </h1>
      );
    case 'h2':
      return (
        <h2
          className="display-font font-semibold mt-6 mb-2 persona-accent"
          style={{
            fontFamily: HEADING_FONT_STACK,
            fontSize: '1.45rem',
            lineHeight: 1.2,
            borderBottom: '1px solid rgb(var(--persona-primary) / 0.35)',
            paddingBottom: '0.25rem',
          }}
        >
          <InlineRender text={block.text} />
        </h2>
      );
    case 'h3':
      return (
        <h3
          className="display-font font-semibold mt-4 mb-1.5 persona-accent"
          style={{ fontFamily: HEADING_FONT_STACK, fontSize: '1.18rem' }}
        >
          <InlineRender text={block.text} />
        </h3>
      );
    case 'h4':
      return (
        <h4
          className="display-font font-semibold mt-3 mb-1 persona-accent"
          style={{ fontFamily: HEADING_FONT_STACK, fontSize: '1.02rem' }}
        >
          <InlineRender text={block.text} />
        </h4>
      );
    case 'p':
      return (
        <p className="leading-relaxed mb-2.5 text-[0.97rem]">
          <InlineRender text={block.text} />
        </p>
      );
    case 'ul':
      return (
        <ul className="mb-3 space-y-1.5 pl-1">
          {block.items.map((it, i) => (
            <li key={i} className="flex items-start gap-2 text-[0.97rem] leading-relaxed">
              <span aria-hidden style={{ color: 'rgb(var(--persona-accent))', flexShrink: 0, marginTop: '0.1em' }}>💕</span>
              <span><InlineRender text={it} /></span>
            </li>
          ))}
        </ul>
      );
    case 'ol':
      return (
        <ol className="mb-3 space-y-1.5 pl-1">
          {block.items.map((it, i) => (
            <li key={i} className="flex items-start gap-2 text-[0.97rem] leading-relaxed">
              <span
                className="font-mono"
                aria-hidden
                style={{
                  color: 'rgb(var(--persona-accent))',
                  flexShrink: 0,
                  minWidth: '1.5em',
                  textAlign: 'right',
                }}
              >
                {i + 1}.
              </span>
              <span><InlineRender text={it} /></span>
            </li>
          ))}
        </ol>
      );
    case 'blockquote':
      return (
        <blockquote
          className="my-3 p-3 rounded-2xl text-[0.97rem]"
          style={{
            background: 'linear-gradient(135deg, rgb(var(--persona-tint)) 0%, rgb(var(--persona-secondary) / 0.55) 100%)',
            borderLeft: '4px solid rgb(var(--persona-accent))',
          }}
        >
          <InlineRender text={block.text} />
        </blockquote>
      );
    case 'code':
      return (
        <pre
          className="my-3 p-3 rounded-2xl text-[0.85rem] overflow-x-auto font-mono"
          style={{
            background: 'rgb(var(--persona-tint))',
            border: '1px solid rgb(var(--persona-primary) / 0.35)',
            whiteSpace: 'pre',
          }}
        >
          <code>{block.text}</code>
        </pre>
      );
    case 'hr':
      return (
        <div className="my-5 flex items-center gap-3" aria-hidden>
          <span className="flex-1 h-px" style={{ background: 'rgb(var(--persona-primary) / 0.35)' }} />
          <span style={{ color: 'rgb(var(--persona-accent))', fontSize: '0.9rem' }}>💕</span>
          <span className="flex-1 h-px" style={{ background: 'rgb(var(--persona-primary) / 0.35)' }} />
        </div>
      );
  }
}

interface TocEntry {
  level: 1 | 2;
  text: string;
  anchor: string;
}

function slug(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .trim()
    .replace(/\s+/g, '-');
}

export function UserManualView() {
  const blocks = useMemo<MdBlock[]>(() => parseMarkdown(manualText), []);
  const toc = useMemo<TocEntry[]>(() => {
    const list: TocEntry[] = [];
    for (const b of blocks) {
      if (b.kind === 'h1' || b.kind === 'h2') {
        list.push({ level: b.kind === 'h1' ? 1 : 2, text: b.text, anchor: slug(b.text) });
      }
    }
    return list;
  }, [blocks]);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const [active, setActive] = useState<string | null>(null);

  function scrollTo(anchor: string) {
    const root = scrollRef.current;
    if (!root) return;
    const target = root.querySelector<HTMLElement>(`[data-anchor="${CSS.escape(anchor)}"]`);
    if (!target) return;
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    setActive(anchor);
  }

  // Track which heading is currently the "active" one in the right rail
  // — pleasant little detail when scrolling through.
  useEffect(() => {
    const root = scrollRef.current;
    if (!root) return;
    const targets = Array.from(root.querySelectorAll<HTMLElement>('[data-anchor]'));
    if (targets.length === 0) return;
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        const first = visible[0];
        if (first) setActive(first.target.getAttribute('data-anchor'));
      },
      { root, rootMargin: '-80px 0px -70% 0px', threshold: 0.1 },
    );
    targets.forEach((t) => observer.observe(t));
    return () => observer.disconnect();
  }, [blocks]);

  return (
    <div className="p-6 max-w-6xl space-y-3">
      <SayingsBanner variant="hero" />

      <div className="flex items-start gap-4">
        <div
          className="flex-1 min-w-0 pretty-card overflow-y-auto"
          style={{ maxHeight: 'calc(100vh - 220px)' }}
          ref={scrollRef}
        >
          {blocks.map((b, i) => {
            if (b.kind === 'h1' || b.kind === 'h2') {
              const anchor = slug(b.text);
              return (
                <div key={i} data-anchor={anchor} style={{ scrollMarginTop: '0.5rem' }}>
                  <BlockRender block={b} />
                </div>
              );
            }
            return <BlockRender key={i} block={b} />;
          })}
        </div>

        {toc.length > 0 && (
          <aside className="hidden lg:block w-60 sticky top-4 self-start">
            <div className="pretty-card">
              <div className="text-xs uppercase tracking-wider opacity-60 mb-2">In this guide</div>
              <ul className="space-y-1 text-sm">
                {toc.map((t) => {
                  const isActive = active === t.anchor;
                  return (
                    <li key={t.anchor} className={t.level === 2 ? 'pl-3' : ''}>
                      <button
                        type="button"
                        onClick={() => scrollTo(t.anchor)}
                        className="text-left w-full hover:opacity-80"
                        style={{
                          color: isActive ? 'rgb(var(--persona-accent))' : 'rgb(var(--persona-text))',
                          fontWeight: isActive ? 600 : 400,
                        }}
                      >
                        {t.text}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>
          </aside>
        )}
      </div>
    </div>
  );
}
