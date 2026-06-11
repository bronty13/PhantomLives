/**
 * @file covers.ts — built-in cover gradients (quiet editorial palette).
 * A page's `cover` field is `gradient:<key>` or `storage:<convex storage id>`.
 */
import type React from 'react';

export const COVER_GRADIENTS: Record<string, string> = {
  iris: 'linear-gradient(118deg, #8d77dd 0%, #4a3690 100%)',
  dawn: 'linear-gradient(118deg, #e8b08c 0%, #b3577e 100%)',
  moss: 'linear-gradient(118deg, #9cb68f 0%, #44603e 100%)',
  ink: 'linear-gradient(118deg, #3d3a52 0%, #16141f 100%)',
  sand: 'linear-gradient(118deg, #e7d9bd 0%, #b59a6a 100%)',
  sea: 'linear-gradient(118deg, #86b3c7 0%, #2e5f78 100%)',
  rose: 'linear-gradient(118deg, #dfb6c8 0%, #9a5878 100%)',
  ember: 'linear-gradient(118deg, #d98e6a 0%, #8a3d2c 100%)'
};

export function coverStyle(cover: string | null | undefined, fileUrl?: string | null): React.CSSProperties | null {
  if (!cover) return null;
  if (cover.startsWith('gradient:')) {
    const g = COVER_GRADIENTS[cover.slice('gradient:'.length)];
    return g ? { backgroundImage: g } : null;
  }
  if (cover.startsWith('storage:') && fileUrl) {
    return { backgroundImage: `url("${fileUrl}")` };
  }
  return null;
}
