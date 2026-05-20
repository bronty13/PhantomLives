/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_MOLLY_DEV?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
