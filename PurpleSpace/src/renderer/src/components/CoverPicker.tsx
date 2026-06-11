import React, { useRef, useState } from 'react';
import { useConvex } from 'convex/react';
import { api } from '../../../../convex/_generated/api';
import { COVER_GRADIENTS } from '../lib/covers';
import { Popover } from './Popover';

interface CoverPickerProps {
  at: { x: number; y: number };
  onPick: (cover: string) => void;
  onClose: () => void;
}

export default function CoverPicker({ at, onPick, onClose }: CoverPickerProps): React.JSX.Element {
  const convex = useConvex();
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const uploadCover = async (file: File): Promise<void> => {
    setUploading(true);
    try {
      const uploadUrl = await convex.mutation(api.files.generateUploadUrl, {});
      const res = await fetch(uploadUrl, {
        method: 'POST',
        headers: { 'Content-Type': file.type || 'application/octet-stream' },
        body: file
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { storageId } = (await res.json()) as { storageId: string };
      onPick(`storage:${storageId}`);
    } finally {
      setUploading(false);
    }
  };

  return (
    <Popover at={at} onClose={onClose}>
      <div className="cover-grid">
        {Object.entries(COVER_GRADIENTS).map(([key, css]) => (
          <button
            key={key}
            className="cover-swatch"
            style={{ backgroundImage: css }}
            title={key}
            onClick={() => onPick(`gradient:${key}`)}
          />
        ))}
      </div>
      <div className="cover-pop-foot">
        <button className="btn" style={{ flex: 1 }} disabled={uploading} onClick={() => fileRef.current?.click()}>
          {uploading ? 'Uploading…' : 'Upload image…'}
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          style={{ display: 'none' }}
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) void uploadCover(f);
          }}
        />
      </div>
    </Popover>
  );
}
