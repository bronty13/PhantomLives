import { PREVIEW_BREAKPOINTS, PROFILE_WIDTH, LISTING_MAX_WIDTH, type DocType } from '../../shared/model';

function capFor(docType: DocType, width: number): number {
  const max = docType === 'listing' ? LISTING_MAX_WIDTH : PROFILE_WIDTH;
  return Math.min(width, max);
}

function PreviewFrame({ html, width, cap }: { html: string; width: number; cap: number }) {
  // Isolated document so the app's CSS can't leak in; approximate NiteFlirt's
  // default Arial stack on a white background.
  const wrapped =
    `<!doctype html><html><head><meta charset="utf-8">` +
    `<style>html,body{margin:0}body{font-family:Arial,Helvetica,sans-serif;color:#000;background:#fff;padding:8px}` +
    `img{max-width:100%}.nf{max-width:${cap}px;margin:0 auto}</style></head>` +
    `<body><div class="nf">${html}</div></body></html>`;
  return (
    <div className="pv-col">
      <div className="pv-label">{width}px</div>
      <div className="pv-frame" style={{ width }}>
        <iframe title={`preview-${width}`} srcDoc={wrapped} />
      </div>
    </div>
  );
}

export function Preview3Up({ html, docType }: { html: string; docType: DocType }) {
  return (
    <div className="preview3up">
      {PREVIEW_BREAKPOINTS.map((w) => (
        <PreviewFrame key={w} html={html} width={w} cap={capFor(docType, w)} />
      ))}
    </div>
  );
}
