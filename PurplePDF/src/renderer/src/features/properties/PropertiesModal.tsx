import { useEffect, useState } from 'react';

export interface DocProperties {
  title: string;
  author: string;
  subject: string;
  keywords: string;
  language: string;
}

interface Props {
  open: boolean;
  initial: DocProperties;
  onCancel: () => void;
  onConfirm: (props: DocProperties) => void;
}

const COMMON_LANGS = [
  { value: '', label: '(unset)' },
  { value: 'en-US', label: 'English (US)' },
  { value: 'en-GB', label: 'English (UK)' },
  { value: 'es-ES', label: 'Spanish' },
  { value: 'fr-FR', label: 'French' },
  { value: 'de-DE', label: 'German' },
  { value: 'it-IT', label: 'Italian' },
  { value: 'pt-BR', label: 'Portuguese (Brazil)' },
  { value: 'ja-JP', label: 'Japanese' },
  { value: 'zh-CN', label: 'Chinese (Simplified)' }
];

export default function PropertiesModal({
  open,
  initial,
  onCancel,
  onConfirm
}: Props): JSX.Element | null {
  const [props, setProps] = useState<DocProperties>(initial);

  useEffect(() => {
    if (open) setProps(initial);
  }, [open, initial]);

  if (!open) return null;

  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal properties-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <h3>Document properties</h3>
          <button className="modal-close" onClick={onCancel} aria-label="Close">
            ×
          </button>
        </div>
        <div className="properties-body">
          <p className="properties-note">
            Properties are written into the document on next Save. Setting a title and language
            improves screen-reader and search engine behavior.
          </p>
          <label className="properties-row">
            <span>Title</span>
            <input
              type="text"
              value={props.title}
              onChange={(e) => setProps({ ...props, title: e.target.value })}
              autoFocus
            />
          </label>
          <label className="properties-row">
            <span>Author</span>
            <input
              type="text"
              value={props.author}
              onChange={(e) => setProps({ ...props, author: e.target.value })}
            />
          </label>
          <label className="properties-row">
            <span>Subject</span>
            <input
              type="text"
              value={props.subject}
              onChange={(e) => setProps({ ...props, subject: e.target.value })}
            />
          </label>
          <label className="properties-row">
            <span>Keywords (comma separated)</span>
            <input
              type="text"
              value={props.keywords}
              onChange={(e) => setProps({ ...props, keywords: e.target.value })}
            />
          </label>
          <label className="properties-row">
            <span>Language</span>
            <div className="properties-lang">
              <select
                value={COMMON_LANGS.some((l) => l.value === props.language) ? props.language : ''}
                onChange={(e) => setProps({ ...props, language: e.target.value })}
              >
                {COMMON_LANGS.map((l) => (
                  <option key={l.value || 'unset'} value={l.value}>
                    {l.label}
                  </option>
                ))}
              </select>
              <input
                type="text"
                placeholder="or custom BCP-47 (e.g. nl-NL)"
                value={props.language}
                onChange={(e) => setProps({ ...props, language: e.target.value })}
              />
            </div>
          </label>
        </div>
        <div className="modal-actions">
          <button type="button" onClick={onCancel}>
            Cancel
          </button>
          <button type="button" className="primary" onClick={() => onConfirm(props)}>
            Apply
          </button>
        </div>
      </div>
    </div>
  );
}
