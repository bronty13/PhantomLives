import type { ReactNode } from 'react';

export function Modal({ title, onClose, children, footer, wide }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  return (
    <div className="backdrop center" onClick={onClose}>
      <div className="modal" style={wide ? { width: 760 } : undefined} onClick={(e) => e.stopPropagation()}>
        <header>
          <h2>{title}</h2>
          <div style={{ flex: 1 }} />
          <button className="ghost" onClick={onClose}>✕</button>
        </header>
        <div className="body">{children}</div>
        {footer && <footer>{footer}</footer>}
      </div>
    </div>
  );
}

export function Drawer({ title, onClose, children, footer }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="backdrop" onClick={onClose}>
      <div className="drawer" onClick={(e) => e.stopPropagation()}>
        <header>
          <h2>{title}</h2>
          <div style={{ flex: 1 }} />
          <button className="ghost" onClick={onClose}>✕</button>
        </header>
        <div className="body">{children}</div>
        {footer && <footer>{footer}</footer>}
      </div>
    </div>
  );
}
