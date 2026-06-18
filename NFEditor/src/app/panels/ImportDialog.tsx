import { useState } from 'react';
import { Modal } from '../components/Modal';
import { importHtml } from '../../shared/import/parse';
import { stripEmoji } from '../../shared/validate/emoji';

export function ImportDialog({
  onImport,
  onClose,
}: {
  onImport: (cleanedHtml: string) => void;
  onClose: () => void;
}) {
  const [raw, setRaw] = useState('');
  const result = raw.trim() ? importHtml(raw) : null;

  const doImport = () => {
    if (!result) return;
    // The editor blocks emoji anyway; strip them from the import so nothing is lost.
    onImport(stripEmoji(result.cleaned));
  };

  return (
    <Modal
      title="Import an existing listing"
      onClose={onClose}
      wide
      footer={
        <>
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" onClick={doImport} disabled={!result}>
            Import
          </button>
        </>
      }
    >
      <p className="hint">
        Paste the HTML of a Profile or Listing you already have. NFEditor parses it into editable blocks and
        flags anything NiteFlirt would strip.
      </p>
      <textarea
        className="import-input"
        value={raw}
        onChange={(e) => setRaw(e.target.value)}
        placeholder="<table>...</table>"
        spellCheck={false}
      />
      {result && (
        <div className="import-report">
          {result.emoji.length > 0 && (
            <div className="alert danger">
              ⚠ {result.emoji.length} emoji found — they will be removed on import (NiteFlirt would otherwise
              truncate your page).
            </div>
          )}
          {result.report.messages.length === 0 ? (
            <div className="alert ok">✓ Nothing will be stripped.</div>
          ) : (
            result.report.messages.map((m, i) => (
              <div key={i} className="alert warn">
                {m}
              </div>
            ))
          )}
        </div>
      )}
    </Modal>
  );
}
