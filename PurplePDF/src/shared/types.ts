// Types shared between main, preload, and renderer. Keep dependency-free.

export interface RecentFile {
  path: string;
  name: string;
  openedAt: number;
}

export interface LoadedFile {
  path: string;
  name: string;
  data: ArrayBuffer;
}

export type ZoomCmd = 'in' | 'out' | 'reset' | 'fit-width' | 'fit-page';
export type RotateCmd = 'cw' | 'ccw';
export type PageCmd = 'next' | 'prev' | 'first' | 'last';
