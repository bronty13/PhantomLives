# Repository Change Management Instructions

When making code or configuration changes in this repository, always apply release hygiene updates in the same change set.

## Mandatory Rules

1. Always update the version number when behavior, interface, configuration, scripts, tests, or docs change.
2. Always update release notes/changelog entries describing what changed and why.
3. Always review and update documentation affected by the change, including at minimum:
   - README.md
   - USER_MANUAL.md (or equivalent user docs)
4. Always update in-code version references and comments that describe behavior changed by the patch.
5. Always update related tests (or add new tests) for bug fixes, regressions, and new behavior.
6. Always update operational/support files when relevant, including config defaults, installer scripts, helper/viewer scripts, and command help text.
7. Never leave a behavior change undocumented.

## Required Pre-Commit Checklist

Before finalizing changes, verify all of the following:

- Version bumped consistently across scripts, docs, and any visible version output.
- Changelog/release notes updated for the new version.
- README and user manual reflect the current behavior.
- Tests added/updated and passing for the changed behavior.
- Config, install, and runtime scripts remain consistent with docs.
- Any user-facing command output/help text matches current functionality.

If any item is not applicable, explicitly state why in the PR/commit notes.
