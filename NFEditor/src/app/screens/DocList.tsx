import type { NFDocument } from '../../shared/model';
import { TEMPLATES } from '../../shared/templates';

export function DocList({
  docs,
  onNew,
  onNewFromTemplate,
  onOpen,
  onDelete,
}: {
  docs: NFDocument[];
  onNew: (docType: 'profile' | 'listing') => void;
  onNewFromTemplate: (templateId: string) => void;
  onOpen: (id: string) => void;
  onDelete: (id: string) => void;
}) {
  return (
    <div className="doclist">
      <section>
        <h2>Start something new</h2>
        <div className="new-row">
          <button className="primary big" onClick={() => onNew('profile')}>
            + Flirt Profile
            <small>up to 7,000 characters</small>
          </button>
          <button className="primary big" onClick={() => onNew('listing')}>
            + Listing
            <small>up to 14,000 characters</small>
          </button>
        </div>
      </section>

      <section>
        <h2>Start from a template</h2>
        <div className="template-grid">
          {TEMPLATES.map((t) => (
            <button key={t.id} className="template-card" onClick={() => onNewFromTemplate(t.id)}>
              <span className={`badge ${t.docType}`}>{t.docType === 'profile' ? 'Profile' : 'Listing'}</span>
              <strong>{t.name}</strong>
              <span className="tmpl-desc">{t.description}</span>
            </button>
          ))}
        </div>
      </section>

      <section>
        <h2>Your documents</h2>
        {docs.length === 0 ? (
          <p className="hint">Nothing saved yet. Create a Profile or Listing above.</p>
        ) : (
          <ul className="saved-list">
            {docs.map((d) => (
              <li key={d.id}>
                <button className="saved-open" onClick={() => onOpen(d.id)}>
                  <span className={`badge ${d.docType}`}>{d.docType === 'profile' ? 'Profile' : 'Listing'}</span>
                  <strong>{d.name || 'Untitled'}</strong>
                  <span className="saved-date">{new Date(d.updatedAt).toLocaleString()}</span>
                </button>
                <button
                  className="ghost danger"
                  title="Delete"
                  onClick={() => {
                    if (confirm(`Delete "${d.name || 'Untitled'}"? This can't be undone.`)) onDelete(d.id);
                  }}
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
