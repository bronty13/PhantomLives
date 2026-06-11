/**
 * @file Popover.tsx — anchored popover + menu primitives (no portal lib;
 * fixed-position with viewport clamping and a click-away backdrop).
 */
import React, { useLayoutEffect, useRef, useState } from 'react';

interface PopoverProps {
  at: { x: number; y: number };
  onClose: () => void;
  children: React.ReactNode;
  className?: string;
}

export function Popover({ at, onClose, children, className }: PopoverProps): React.JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState(at);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    setPos({
      x: Math.max(8, Math.min(at.x, window.innerWidth - r.width - 8)),
      y: Math.max(8, Math.min(at.y, window.innerHeight - r.height - 8))
    });
  }, [at]);

  return (
    <>
      <div
        className="pop-backdrop"
        onMouseDown={(e) => {
          e.stopPropagation();
          onClose();
        }}
      />
      <div ref={ref} className={`popover ${className ?? ''}`} style={{ left: pos.x, top: pos.y }}>
        {children}
      </div>
    </>
  );
}

interface MenuProps extends PopoverProps {
  children: React.ReactNode;
}

interface MenuCtx {
  close: () => void;
}
const MenuContext = React.createContext<MenuCtx>({ close: () => {} });

export function Menu({ at, onClose, children }: MenuProps): React.JSX.Element {
  return (
    <Popover at={at} onClose={onClose} className="menu">
      <MenuContext.Provider value={{ close: onClose }}>{children}</MenuContext.Provider>
    </Popover>
  );
}

interface MenuItemProps {
  icon?: React.ReactNode;
  label: string;
  danger?: boolean;
  keepOpen?: boolean;
  onClick: () => void;
}

export function MenuItem({ icon, label, danger, keepOpen, onClick }: MenuItemProps): React.JSX.Element {
  const { close } = React.useContext(MenuContext);
  return (
    <button
      className={`menu-item ${danger ? 'danger' : ''}`}
      onClick={() => {
        onClick();
        if (!keepOpen) close();
      }}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
}

export function MenuSep(): React.JSX.Element {
  return <div className="menu-sep" />;
}

export function MenuNote({ children }: { children: React.ReactNode }): React.JSX.Element {
  return <div className="menu-note">{children}</div>;
}
