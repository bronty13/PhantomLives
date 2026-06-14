import { useState } from 'react';

/**
 * A red error banner whose text Sallie can copy with one click, so she can
 * paste the exact message to Robert instead of sending a phone photo / HEIC
 * screenshot he can't read back. Used wherever a media/engine error surfaces
 * (GIF Studio today; reusable elsewhere).
 */
export function CopyableError({ message }: { message: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(message).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      },
      () => {
        /* clipboard blocked — nothing we can do, the text is still on screen */
      },
    );
  };
  return (
    <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2 flex items-start gap-2">
      <span className="flex-1 whitespace-pre-wrap break-words">{message}</span>
      <button
        type="button"
        onClick={copy}
        className="shrink-0 text-xs font-semibold text-red-700 border border-red-300 rounded-lg px-2 py-1 hover:bg-red-100"
        title="Copy this error to send to Robert"
      >
        {copied ? '✓ Copied' : '📋 Copy'}
      </button>
    </div>
  );
}
