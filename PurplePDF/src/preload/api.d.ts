import type { PurplePDFApi } from './index';

declare global {
  interface Window {
    purplePDF: PurplePDFApi;
  }
}

export {};
