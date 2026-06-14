// The running build's human version, used by the in-app update banner and the
// What's New popup to decide whether a hosted deploy is newer than this build.
//
// KEEP IN SYNC with `version` in package.json. The deploy script
// (scripts/deploy-pages.sh) refuses to publish when these two drift, because the
// banner compares APP_VERSION against the deployed version.json (which is derived
// from package.json) — a mismatch would make the banner lie.
export const APP_VERSION = '0.4.0';

/** Display name, used in the update banner copy. */
export const APP_NAME = 'Quizzer';
