import React, { Suspense } from 'react';
import { Popover } from './Popover';
import { useIsDark } from '../lib/useIsDark';

// emoji-picker-react is ~300KB — lazy-load so first paint stays fast.
const EmojiPicker = React.lazy(() => import('emoji-picker-react'));

interface IconPickerProps {
  at: { x: number; y: number };
  hasIcon: boolean;
  onPick: (emoji: string) => void;
  onRemove: () => void;
  onClose: () => void;
}

export default function IconPicker({ at, hasIcon, onPick, onRemove, onClose }: IconPickerProps): React.JSX.Element {
  const dark = useIsDark();
  return (
    <Popover at={at} onClose={onClose}>
      <Suspense fallback={<div style={{ width: 350, height: 400 }} />}>
        <EmojiPicker
          theme={(dark ? 'dark' : 'light') as never}
          width={350}
          height={400}
          lazyLoadEmojis
          previewConfig={{ showPreview: false }}
          onEmojiClick={(e) => onPick(e.emoji)}
        />
      </Suspense>
      {hasIcon && (
        <div style={{ padding: 8, borderTop: '1px solid var(--line)' }}>
          <button className="btn danger" style={{ width: '100%' }} onClick={onRemove}>
            Remove icon
          </button>
        </div>
      )}
    </Popover>
  );
}
