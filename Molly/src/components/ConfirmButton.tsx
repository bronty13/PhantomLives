import { useState } from 'react';

interface Props {
  label: string;
  confirmLabel?: string;
  onConfirm: () => void | Promise<void>;
  className?: string;
  variant?: 'danger' | 'secondary';
  disabled?: boolean;
  title?: string;
}

export function ConfirmButton({ label, confirmLabel = 'Sure?', onConfirm, className, variant = 'danger', disabled, title }: Props) {
  const [armed, setArmed] = useState(false);
  return (
    <button
      type="button"
      disabled={disabled}
      title={title}
      onClick={async () => {
        if (!armed) {
          setArmed(true);
          setTimeout(() => setArmed(false), 3000);
          return;
        }
        await onConfirm();
        setArmed(false);
      }}
      className={`pretty-button ${variant === 'danger' ? 'danger' : 'secondary'} ${className ?? ''}`}
    >
      {armed ? confirmLabel : label}
    </button>
  );
}
