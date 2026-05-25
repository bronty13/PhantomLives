/**
 * @file SettingsWindow.tsx — modal settings UI. Currently ships with a
 * single "Stamps" tab; tab framework is in place so future settings
 * (General / Updates / About) can drop in without redesign.
 */

import { useEffect, useState } from 'react';
import StampsTab from './tabs/StampsTab';

interface Props {
  /** Initial tab to focus when opening. */
  initialTab?: SettingsTabId;
  onClose: () => void;
}

export type SettingsTabId = 'stamps';

const TABS: { id: SettingsTabId; label: string; icon: string }[] = [
  { id: 'stamps', label: 'Stamps', icon: '✪' }
];

export default function SettingsWindow({ initialTab = 'stamps', onClose }: Props): JSX.Element {
  const [tab, setTab] = useState<SettingsTabId>(initialTab);

  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        className="modal settings-modal"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
      >
        <div className="modal-head">
          <h3 id="settings-title">Preferences</h3>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
            ×
          </button>
        </div>
        <div className="settings-body">
          <nav className="settings-tabs" role="tablist" aria-label="Settings tabs">
            {TABS.map((t) => (
              <button
                key={t.id}
                type="button"
                role="tab"
                aria-selected={tab === t.id}
                className={`settings-tab${tab === t.id ? ' active' : ''}`}
                onClick={() => setTab(t.id)}
              >
                <span aria-hidden="true">{t.icon}</span>
                <span>{t.label}</span>
              </button>
            ))}
          </nav>
          <div className="settings-pane" role="tabpanel">
            {tab === 'stamps' && <StampsTab />}
          </div>
        </div>
      </div>
    </div>
  );
}
