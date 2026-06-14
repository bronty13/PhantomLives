import type { ReactNode } from 'react';

// A tiny, dependency-free Markdown renderer for our own trusted docs (the in-app
// USER_MANUAL). Supports the subset we actually author: # ## ### #### headings,
// `-`/`*` bullet lists, `1.` numbered lists, blank-line paragraphs, `---` rules,
// and inline **bold**, `code`, and [links](url). Intentionally not a full parser.

function renderInline(text: string, keyBase: string): ReactNode[] {
  const out: ReactNode[] = [];
  // Tokenize bold / code / link / italic; everything else is literal text.
  // Bold (**…**) is listed before italic (*…*) so the double-star wins.
  const re = /(\*\*([^*]+)\*\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)]+)\))|(\*([^*]+)\*)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let i = 0;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[2] !== undefined) {
      out.push(<strong key={`${keyBase}-b${i}`}>{m[2]}</strong>);
    } else if (m[4] !== undefined) {
      out.push(<code key={`${keyBase}-c${i}`} style={{ background: 'var(--line, #eee)', padding: '1px 5px', borderRadius: 4 }}>{m[4]}</code>);
    } else if (m[6] !== undefined && m[7] !== undefined) {
      out.push(<a key={`${keyBase}-l${i}`} href={m[7]} target="_blank" rel="noreferrer">{m[6]}</a>);
    } else if (m[9] !== undefined) {
      out.push(<em key={`${keyBase}-i${i}`}>{m[9]}</em>);
    }
    last = m.index + m[0].length;
    i++;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function Markdown({ md, baseFontSize = 18 }: { md: string; baseFontSize?: number }) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const blocks: ReactNode[] = [];
  let para: string[] = [];
  let list: { ordered: boolean; items: string[] } | null = null;
  let key = 0;

  const flushPara = () => {
    if (para.length) {
      blocks.push(<p key={`p${key++}`} style={{ margin: '0 0 14px' }}>{renderInline(para.join(' '), `p${key}`)}</p>);
      para = [];
    }
  };
  const flushList = () => {
    if (list) {
      const items = list.items.map((it, idx) => (
        <li key={idx} style={{ marginBottom: 8 }}>{renderInline(it, `li${key}-${idx}`)}</li>
      ));
      blocks.push(
        list.ordered
          ? <ol key={`l${key++}`} style={{ margin: '0 0 16px', paddingLeft: 28 }}>{items}</ol>
          : <ul key={`l${key++}`} style={{ margin: '0 0 16px', paddingLeft: 28 }}>{items}</ul>,
      );
      list = null;
    }
  };

  for (const raw of lines) {
    const line = raw.trimEnd();
    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    const bullet = /^[-*]\s+(.*)$/.exec(line);
    const numbered = /^\d+\.\s+(.*)$/.exec(line);

    if (line.trim() === '') {
      flushPara(); flushList();
      continue;
    }
    if (line.trim() === '---') {
      flushPara(); flushList();
      blocks.push(<hr key={`hr${key++}`} style={{ border: 'none', borderTop: '1px solid var(--line, #ddd)', margin: '18px 0' }} />);
      continue;
    }
    if (heading) {
      flushPara(); flushList();
      const level = heading[1].length;
      const sizes = [0, 28, 23, 19, 17];
      blocks.push(
        <div key={`h${key++}`} style={{ fontSize: sizes[level], fontWeight: 700, margin: level <= 2 ? '22px 0 12px' : '16px 0 8px', lineHeight: 1.3 }}>
          {renderInline(heading[2], `h${key}`)}
        </div>,
      );
      continue;
    }
    if (bullet) {
      flushPara();
      if (!list || list.ordered) { flushList(); list = { ordered: false, items: [] }; }
      list.items.push(bullet[1]);
      continue;
    }
    if (numbered) {
      flushPara();
      if (!list || !list.ordered) { flushList(); list = { ordered: true, items: [] }; }
      list.items.push(numbered[1]);
      continue;
    }
    // Plain text line → part of a paragraph.
    flushList();
    para.push(line.trim());
  }
  flushPara(); flushList();

  return <div style={{ fontSize: baseFontSize, lineHeight: 1.6 }}>{blocks}</div>;
}
