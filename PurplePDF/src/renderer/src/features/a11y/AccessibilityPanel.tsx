import type { A11yReport } from './checks';

interface Props {
  report: A11yReport | null;
  loading: boolean;
  onRecheck: () => void;
  onOpenProperties: () => void;
}

const ICON: Record<string, string> = {
  pass: '✓',
  warn: '⚠',
  fail: '✗',
  info: 'ℹ'
};

export default function AccessibilityPanel({
  report,
  loading,
  onRecheck,
  onOpenProperties
}: Props): JSX.Element {
  return (
    <div className="a11y-panel">
      <div className="a11y-head">
        <div className="a11y-summary" aria-live="polite">
          {loading
            ? 'Running checks…'
            : report
              ? `${report.pass} pass · ${report.warn} warn · ${report.fail} fail`
              : 'No checks run yet.'}
        </div>
        <div className="a11y-actions">
          <button type="button" onClick={onOpenProperties}>
            Properties…
          </button>
          <button type="button" onClick={onRecheck} disabled={loading}>
            Re-check
          </button>
        </div>
      </div>
      <ul className="a11y-list">
        {report?.checks.map((c) => (
          <li key={c.id} className={`a11y-item sev-${c.severity}`}>
            <div className="a11y-row">
              <span className="a11y-icon" aria-hidden="true">
                {ICON[c.severity]}
              </span>
              <span className="a11y-label">{c.label}</span>
              {c.fixable && (
                <button
                  type="button"
                  className="a11y-fix"
                  onClick={onOpenProperties}
                  title="Open Document Properties to fix"
                >
                  Fix…
                </button>
              )}
            </div>
            <div className="a11y-detail">{c.detail}</div>
          </li>
        ))}
      </ul>
      <p className="a11y-foot">
        Purple PDF accessibility checks cover document-level structure. For tag-level audits
        (headings, table structure, reading order, alt-text) use a dedicated PAC verifier.
      </p>
    </div>
  );
}
