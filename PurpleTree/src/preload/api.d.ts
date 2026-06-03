import type { PurpleTreeApi } from './index';

declare global {
  interface Window {
    purpleTree: PurpleTreeApi;
  }
}

export {};
