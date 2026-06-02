import { useState } from 'react';
import { GifCreator } from './GifCreator';

/** Standalone GIF Studio — a general video→GIF converter, no bundle context.
 * Download-only (no teaser slot to fill). The creator itself is the same
 * component used from a bundle's Teaser field. */
export function GifStudioView() {
  // The creator is the whole tool here; keep it always-mounted. "Close" just
  // resets it by remounting via a key bump.
  const [key, setKey] = useState(0);
  return (
    <div className="p-8 space-y-4 max-w-4xl">
      <header className="space-y-1">
        <h2 className="display-font text-2xl font-bold persona-accent">🎞️ GIF Studio</h2>
        <p className="opacity-70 text-sm">
          Turn a video into an animated GIF — trim it, set the size and speed,
          crop, add a caption, then download. Everything happens right here on
          your machine.
        </p>
      </header>
      <GifCreator key={key} embedded onClose={() => setKey((k) => k + 1)} />
    </div>
  );
}
