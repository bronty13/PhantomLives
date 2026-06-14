import { useState } from 'react';
import { Modal } from './Modal';
import { Markdown } from './Markdown';
import { USER_MANUAL_MD } from '../../data/manual';

/**
 * The in-app User Manual: the committed USER_MANUAL.md rendered large-print and
 * high-contrast. A font-size control helps the low-vision primary user.
 */
export function UserManual({ onClose }: { onClose: () => void }) {
  const [size, setSize] = useState(18);
  return (
    <Modal
      title="User Manual"
      onClose={onClose}
      wide
      footer={
        <>
          <span style={{ fontSize: 14, color: 'var(--muted)' }}>Text size</span>
          <button onClick={() => setSize((s) => Math.max(14, s - 2))} aria-label="Smaller text" style={{ fontSize: 18, padding: '4px 12px' }}>A−</button>
          <button onClick={() => setSize((s) => Math.min(28, s + 2))} aria-label="Larger text" style={{ fontSize: 18, padding: '4px 12px' }}>A+</button>
          <div style={{ flex: 1 }} />
          <button className="primary" style={{ fontSize: 17, padding: '8px 22px' }} onClick={onClose}>Close</button>
        </>
      }
    >
      <Markdown md={USER_MANUAL_MD} baseFontSize={size} />
    </Modal>
  );
}
