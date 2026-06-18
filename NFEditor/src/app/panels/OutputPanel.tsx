import { useMemo, useState } from 'react';
import type { DocNode, OutputMode } from '../../shared/model';
import { serialize } from '../../shared/serialize';

export function OutputPanel({ doc, mode, name }: { doc: DocNode; mode: OutputMode; name: string }) {
  const html = useMemo(() => serialize(doc, mode), [doc, mode]);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(html);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard blocked — user can select the textarea manually */
    }
  };

  const download = () => {
    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${(name || 'nf-listing').replace(/[^a-z0-9_-]+/gi, '-')}.html`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="output">
      <div className="output-actions">
        <button className="primary" onClick={copy}>
          {copied ? 'Copied!' : 'Copy HTML'}
        </button>
        <button className="ghost" onClick={download}>
          Download .html
        </button>
        <span className="hint">Paste into NiteFlirt's HTML box. Save downloads to ~/Downloads/NFEditor/.</span>
      </div>
      <textarea className="output-code" readOnly value={html} spellCheck={false} />
    </div>
  );
}
