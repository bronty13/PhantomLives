import { useState } from 'react';

export interface ProtectOptions {
  userPassword: string;
  ownerPassword: string;
  permissions: {
    print: boolean;
    copy: boolean;
    modify: boolean;
    annotate: boolean;
  };
}

interface Props {
  open: boolean;
  onCancel: () => void;
  onConfirm: (opts: ProtectOptions) => void;
}

export default function ProtectModal({ open, onCancel, onConfirm }: Props): JSX.Element | null {
  const [userPassword, setUserPassword] = useState('');
  const [ownerPassword, setOwnerPassword] = useState('');
  const [showUser, setShowUser] = useState(false);
  const [showOwner, setShowOwner] = useState(false);
  const [print, setPrint] = useState(true);
  const [copy, setCopy] = useState(true);
  const [modify, setModify] = useState(false);
  const [annotate, setAnnotate] = useState(false);

  if (!open) return null;

  const canConfirm = userPassword.length > 0;

  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal protect-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <h3>Protect with password</h3>
          <button className="modal-close" onClick={onCancel} aria-label="Close">
            ×
          </button>
        </div>

        <div className="protect-body">
          <p className="protect-note">
            Encrypts the current document with AES-256 via <code>qpdf</code>. Permission flags below
            are PDF restrictions — note that some PDF tools may bypass them once the file is open.
          </p>

          <label className="protect-row">
            <span>User password (required to open)</span>
            <div className="protect-input-wrap">
              <input
                type={showUser ? 'text' : 'password'}
                value={userPassword}
                onChange={(e) => setUserPassword(e.target.value)}
                autoFocus
              />
              <button type="button" onClick={() => setShowUser((s) => !s)}>
                {showUser ? 'Hide' : 'Show'}
              </button>
            </div>
          </label>

          <label className="protect-row">
            <span>Owner password (controls permissions, optional)</span>
            <div className="protect-input-wrap">
              <input
                type={showOwner ? 'text' : 'password'}
                value={ownerPassword}
                onChange={(e) => setOwnerPassword(e.target.value)}
              />
              <button type="button" onClick={() => setShowOwner((s) => !s)}>
                {showOwner ? 'Hide' : 'Show'}
              </button>
            </div>
          </label>

          <fieldset className="protect-perms">
            <legend>Allow recipients to:</legend>
            <label>
              <input type="checkbox" checked={print} onChange={(e) => setPrint(e.target.checked)} />
              Print
            </label>
            <label>
              <input type="checkbox" checked={copy} onChange={(e) => setCopy(e.target.checked)} />
              Copy text & images
            </label>
            <label>
              <input
                type="checkbox"
                checked={modify}
                onChange={(e) => setModify(e.target.checked)}
              />
              Modify the document
            </label>
            <label>
              <input
                type="checkbox"
                checked={annotate}
                onChange={(e) => setAnnotate(e.target.checked)}
              />
              Annotate & fill forms
            </label>
          </fieldset>

          <p className="protect-warn">
            ⚠ Current annotations, form values, and page edits will be <strong>flattened</strong>{' '}
            into the encrypted output and can no longer be edited from the protected file.
          </p>
        </div>

        <div className="modal-actions">
          <button type="button" onClick={onCancel}>
            Cancel
          </button>
          <button
            type="button"
            className="primary"
            disabled={!canConfirm}
            onClick={() =>
              onConfirm({
                userPassword,
                ownerPassword: ownerPassword || userPassword,
                permissions: { print, copy, modify, annotate }
              })
            }
          >
            Encrypt & Save…
          </button>
        </div>
      </div>
    </div>
  );
}
