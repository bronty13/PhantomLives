// In-app manual. Renders USER_MANUAL.md (bundled at build time via
// Vite's ?raw import) through the shared markdownLite renderer, with a
// sticky right-rail table of contents that anchor-scrolls to sections.

import { useMemo } from 'react';
import manualSource from '../../../USER_MANUAL.md?raw';
import { parseMarkdownLite } from '../../lib/markdownLite';
import { MarkdownBlocks, headingsOf } from '../../components/Markdown';

export function ManualView() {
  const blocks = useMemo(() => parseMarkdownLite(manualSource), []);
  // TOC from H2s (the section level in USER_MANUAL.md). The single H1
  // is the page title, already shown in the header.
  const toc = useMemo(() => headingsOf(blocks).filter((h) => h.level === 2), [blocks]);

  const jumpTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  return (
    <div className="h-full overflow-y-auto">
      <div className="p-8 flex gap-8 max-w-5xl mx-auto">
        <article className="flex-1 min-w-0">
          <h1 className="display-font text-4xl mb-6" style={{ color: 'rgb(var(--surface-accent))' }}>
            Manual
          </h1>
          <MarkdownBlocks blocks={blocks} />
        </article>

        {toc.length > 0 && (
          <nav className="w-52 shrink-0 hidden lg:block">
            <div className="sticky top-8">
              <div className="text-[10px] uppercase tracking-wider mb-2"
                   style={{ color: 'rgb(var(--surface-muted))' }}>
                On this page
              </div>
              <ul className="flex flex-col gap-1">
                {toc.map((h) => (
                  <li key={h.id}>
                    <button
                      type="button"
                      onClick={() => jumpTo(h.id)}
                      className="text-left text-xs leading-snug w-full hover:underline"
                      style={{ color: 'rgb(var(--surface-text) / 0.78)' }}
                    >
                      {h.text}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </nav>
        )}
      </div>
    </div>
  );
}
