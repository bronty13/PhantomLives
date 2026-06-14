import type { ReleaseNote } from '../data/whatsNew';

/**
 * "What's New" popup shown once after an update. Self-contained overlay (Quizzer
 * has no shared Modal): a dimmed backdrop + a centered card, dismissed by the
 * button, the backdrop, or Escape (handled by the caller resetting state).
 */
export function WhatsNew({ notes, onClose }: { notes: ReleaseNote[]; onClose: () => void }) {
  if (notes.length === 0) return null;
  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.45)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
        padding: 16,
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="What's New"
        onClick={(e) => e.stopPropagation()}
        style={{
          background: 'var(--card, #fff)',
          color: 'var(--fg, #1a1a1a)',
          borderRadius: 12,
          maxWidth: 460,
          width: '100%',
          maxHeight: '80vh',
          overflow: 'auto',
          boxShadow: '0 12px 40px rgba(0,0,0,0.3)',
          padding: 24,
        }}
      >
        <h2 style={{ margin: '0 0 16px', fontSize: 22 }}>What&rsquo;s New 🎉</h2>
        <div style={{ fontSize: 15, lineHeight: 1.6 }}>
          {notes.map((note) => (
            <div key={note.version} style={{ marginBottom: 18 }}>
              <div style={{ fontSize: 13, color: 'var(--muted, #777)', marginBottom: 6 }}>
                Version {note.version} · {note.date}
              </div>
              <ul style={{ margin: 0, paddingLeft: 22 }}>
                {note.highlights.map((h, i) => (
                  <li key={i} style={{ marginBottom: 8 }}>
                    {h}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div style={{ textAlign: 'right', marginTop: 8 }}>
          <button
            onClick={onClose}
            style={{
              fontSize: 16,
              padding: '10px 24px',
              background: '#1f6f43',
              color: '#fff',
              border: 'none',
              borderRadius: 8,
              fontWeight: 600,
              cursor: 'pointer',
            }}
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
}
