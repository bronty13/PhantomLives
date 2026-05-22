import { useEffect, useRef, useState } from 'react';

interface Props {
  value: string[];                        // length 24 always; "" for empty cells
  onChange: (next: string[]) => void;
  /** Read-only display mode (export side) vs editable input mode (import). */
  readOnly?: boolean;
}

/**
 * 24-cell BIP-39 mnemonic grid (6 cols × 4 rows). Tab moves left-to-right
 * top-to-bottom; paste into ANY cell of multiple whitespace-separated
 * words spreads them across subsequent cells. Tolerant of "1. " number
 * prefixes (people pasting back their own numbered list).
 *
 * Live validation is left to the caller — this component just owns
 * input + paste mechanics.
 */
export function MnemonicGrid({ value, onChange, readOnly }: Props) {
  // Defensive: always work in a 24-length array.
  const cells = padTo24(value);

  function updateCell(idx: number, raw: string) {
    // Strip a leading "N." or "N)" if present (paste-back tolerance).
    // Then collapse whitespace — a single cell only ever holds one word.
    const cleaned = raw
      .replace(/^\s*\d+\s*[.)]\s*/, '')
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase();
    const parts = cleaned.split(/\s+/).filter((p) => p.length > 0);
    if (parts.length <= 1) {
      const next = cells.slice();
      next[idx] = parts[0] ?? '';
      onChange(next);
      return;
    }
    // User pasted multiple words into one cell — spread.
    spreadFrom(idx, parts);
  }

  function spreadFrom(startIdx: number, parts: string[]) {
    const next = cells.slice();
    for (let i = 0; i < parts.length && startIdx + i < 24; i++) {
      // Each part can itself have a "N." prefix if they copied a
      // numbered list — strip again per token.
      const word = parts[i].replace(/^\s*\d+\s*[.)]\s*/, '').toLowerCase().trim();
      next[startIdx + i] = word;
    }
    onChange(next);
    // Move focus to the next empty cell after the spread.
    const focusIdx = Math.min(startIdx + parts.length, 23);
    queueFocus(focusIdx);
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>, idx: number) {
    if (e.key === 'Backspace' && cells[idx] === '' && idx > 0) {
      e.preventDefault();
      queueFocus(idx - 1);
    } else if (e.key === 'ArrowLeft' && (e.currentTarget.selectionStart ?? 0) === 0 && idx > 0) {
      e.preventDefault();
      queueFocus(idx - 1);
    } else if (e.key === 'ArrowRight' && (e.currentTarget.selectionStart ?? 0) === cells[idx].length && idx < 23) {
      e.preventDefault();
      queueFocus(idx + 1);
    } else if ((e.key === ' ' || e.key === 'Enter') && cells[idx].length > 0 && idx < 23) {
      // Space-to-advance — most natural typing flow.
      e.preventDefault();
      queueFocus(idx + 1);
    }
  }

  function handlePaste(e: React.ClipboardEvent<HTMLInputElement>, idx: number) {
    const text = e.clipboardData.getData('text');
    const parts = text.split(/\s+/).filter((p) => p.length > 0);
    if (parts.length > 1) {
      e.preventDefault();
      spreadFrom(idx, parts);
    }
  }

  // Refs for focus management.
  const inputRefs = useRef<Array<HTMLInputElement | null>>(Array(24).fill(null));
  const [pendingFocus, setPendingFocus] = useState<number | null>(null);
  function queueFocus(idx: number) { setPendingFocus(idx); }
  useEffect(() => {
    if (pendingFocus == null) return;
    const el = inputRefs.current[pendingFocus];
    if (el) {
      el.focus();
      el.select();
    }
    setPendingFocus(null);
  }, [pendingFocus]);

  async function pasteFromClipboard() {
    try {
      const text = await navigator.clipboard.readText();
      const parts = text.split(/\s+/).filter((p) => p.length > 0);
      if (parts.length === 0) return;
      spreadFrom(0, parts);
    } catch {
      // Clipboard read denied — ignore quietly; user can still paste into a cell.
    }
  }

  function clearAll() {
    onChange(Array(24).fill(''));
    queueFocus(0);
  }

  return (
    <div className="space-y-2">
      {!readOnly && (
        <div className="flex items-center justify-between text-xs">
          <span className="opacity-60">
            Tip: paste anywhere, or type a word and press space / Enter to jump to the next cell.
          </span>
          <div className="flex gap-2">
            <button type="button" onClick={pasteFromClipboard} className="pretty-button secondary text-xs">
              📋 Paste from clipboard
            </button>
            <button type="button" onClick={clearAll} className="pretty-button secondary text-xs">
              Clear all
            </button>
          </div>
        </div>
      )}
      <div className="grid grid-cols-4 sm:grid-cols-6 gap-1.5 bg-pink-50 rounded-xl p-3">
        {cells.map((word, i) => (
          <label key={i} className="flex items-center gap-1 text-xs font-mono">
            <span className="opacity-50 w-6 text-right select-none">{i + 1}.</span>
            <input
              ref={(el) => { inputRefs.current[i] = el; }}
              type="text"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              className="flex-1 bg-white border border-pink-200 rounded px-1.5 py-1 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-pink-300"
              value={word}
              onChange={(e) => updateCell(i, e.target.value)}
              onKeyDown={(e) => handleKeyDown(e, i)}
              onPaste={(e) => handlePaste(e, i)}
              readOnly={readOnly}
              tabIndex={readOnly ? -1 : 0}
            />
          </label>
        ))}
      </div>
    </div>
  );
}

function padTo24(value: string[]): string[] {
  const out = value.slice(0, 24);
  while (out.length < 24) out.push('');
  return out;
}
