import type { PurpleChefApi } from './index';

declare global {
  interface Window {
    purpleChef: PurpleChefApi;
  }
}

export {};
