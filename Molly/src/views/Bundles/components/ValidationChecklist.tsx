import type { ValidationIssue } from '../../../lib/bundleValidation';

interface Props {
  issues: ValidationIssue[];
  onJump?: () => void;                    // optional hook for "close the wizard before scrolling"
}

/** Renders the per-field list of issues with click-to-jump. Errors
 * render in red, warnings in amber. Clicking an issue scrolls + focuses
 * the corresponding form field (the form gives each field a stable id;
 * the validators carry that id back as jumpToFieldId). */
export function ValidationChecklist({ issues, onJump }: Props) {
  if (issues.length === 0) {
    return (
      <div className="text-sm text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-2xl px-4 py-3">
        ✨ All checks pass — ready to publish.
      </div>
    );
  }
  return (
    <ul className="space-y-1">
      {issues.map((iss, idx) => {
        const isErr = iss.severity === 'error';
        return (
          <li key={`${iss.fieldPath}-${idx}`}>
            <button
              type="button"
              onClick={() => {
                onJump?.();
                const el = document.getElementById(iss.jumpToFieldId);
                if (el) {
                  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  // Defer focus a tick so the scroll has time to start.
                  setTimeout(() => {
                    if (el instanceof HTMLElement) el.focus({ preventScroll: true });
                  }, 80);
                }
              }}
              className="w-full text-left px-3 py-2 rounded-xl border transition flex items-start gap-2 text-sm"
              style={{
                background: isErr ? '#FEF2F2' : '#FFFBEB',
                borderColor: isErr ? '#FECACA' : '#FDE68A',
                color: isErr ? '#991B1B' : '#92400E',
              }}
              title={`Jump to ${iss.fieldPath}`}
            >
              <span aria-hidden className="leading-5">{isErr ? '⛔' : '⚠️'}</span>
              <span className="flex-1">
                <span className="font-medium">{iss.message}</span>
                <span className="opacity-60 ml-2 text-xs font-mono">{iss.fieldPath}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
