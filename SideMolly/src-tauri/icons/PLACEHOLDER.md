# Placeholder icons

Every PNG / ICNS / ICO in this directory was **copied from Molly** so
the first `pnpm tauri build` succeeds (Tauri refuses to build without
the icons declared in `tauri.conf.json::bundle.icon`).

**Before the first signed release**, replace them with SideMolly's
own design. Workflow:

1. Drop a 1024x1024 PNG named `sidemolly-icon-source.png` into
   `src-tauri/icons/`.
2. Run `pnpm tauri icon src-tauri/icons/sidemolly-icon-source.png`.
3. Delete this file.

See `SideMolly/CHANGELOG.md` for the Phase 0 note.
