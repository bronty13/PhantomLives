// Single source of truth for the in-app help: the project's USER_MANUAL.md is
// inlined at build time so it ships inside the offline single-file app and can
// never drift from the committed doc.
import md from '../../USER_MANUAL.md?raw';

export const USER_MANUAL_MD: string = md;
