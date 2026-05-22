import { useEffect } from 'react';

interface Props {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Renders the confirm button in danger styling for destructive ops. */
  danger?: boolean;
  onConfirm: () => void | Promise<void>;
  onCancel: () => void;
}

/** Tauri-safe replacement for window.confirm. */
export function ConfirmModal({
  title, message, confirmLabel = 'Confirm', cancelLabel = 'Cancel',
  danger = false, onConfirm, onCancel,
}: Props) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onCancel();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm"
      onClick={onCancel}
    >
      <div
        className="rounded-3xl bg-white shadow-2xl border border-black/10 p-5 w-[420px] max-w-[90vw]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-3">
          <h3 className="display-font text-lg font-semibold persona-accent">{title}</h3>
          <button type="button" onClick={onCancel} className="opacity-50 hover:opacity-100 text-xl leading-none">×</button>
        </div>
        <p className="text-sm opacity-80 whitespace-pre-wrap">{message}</p>
        <div className="flex justify-end gap-2 mt-4">
          <button type="button" onClick={onCancel} className="pretty-button secondary">
            {cancelLabel}
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className={`pretty-button ${danger ? 'danger' : ''}`}
            autoFocus
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
