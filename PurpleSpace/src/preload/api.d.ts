import type { PurpleSpaceApi } from './index';

declare global {
  interface Window {
    purpleSpace: PurpleSpaceApi;
  }
}

export {};
