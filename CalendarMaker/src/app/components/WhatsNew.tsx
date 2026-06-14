import { Modal } from './Modal';
import type { ReleaseNote } from '../../data/whatsNew';

/**
 * Large-print "What's New" popup shown once after an update. Tuned for low vision:
 * big text, high contrast, generous spacing, one obvious close button.
 */
export function WhatsNew({ notes, onClose }: { notes: ReleaseNote[]; onClose: () => void }) {
  if (notes.length === 0) return null;
  return (
    <Modal
      title="What's New 🎉"
      onClose={onClose}
      footer={<button className="primary" style={{ fontSize: 18, padding: '10px 24px' }} onClick={onClose}>Got it</button>}
    >
      <div style={{ fontSize: 17, lineHeight: 1.6 }}>
        {notes.map((note) => (
          <div key={note.version} style={{ marginBottom: 18 }}>
            <div style={{ fontSize: 15, color: 'var(--muted)', marginBottom: 6 }}>
              Version {note.version} · {note.date}
            </div>
            <ul style={{ margin: 0, paddingLeft: 24 }}>
              {note.highlights.map((h, i) => (
                <li key={i} style={{ marginBottom: 10 }}>{h}</li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </Modal>
  );
}
