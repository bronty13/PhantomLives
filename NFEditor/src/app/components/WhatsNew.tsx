import { Modal } from './Modal';
import type { ReleaseNote } from '../../shared/whatsNew';

export function WhatsNew({ notes, onClose }: { notes: ReleaseNote[]; onClose: () => void }) {
  if (notes.length === 0) return null;
  return (
    <Modal
      title="What's New 🎉"
      onClose={onClose}
      footer={
        <button className="primary" onClick={onClose}>
          Got it
        </button>
      }
    >
      {notes.map((note) => (
        <div key={note.version} className="wn-entry">
          <div className="wn-ver">
            Version {note.version} · {note.date}
          </div>
          <ul>
            {note.highlights.map((h, i) => (
              <li key={i}>{h}</li>
            ))}
          </ul>
        </div>
      ))}
    </Modal>
  );
}
