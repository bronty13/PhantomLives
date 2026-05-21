# Purple PDF — Install Guide

This guide is for end users. Developers should see [README.md](../README.md).

## macOS

1. Download `Purple PDF-1.0.0-universal.dmg` from the
   [Releases page](https://github.com/bronty13/PhantomLives/releases).
2. Open the DMG and drag **Purple PDF** to `/Applications`.
3. First launch may prompt Gatekeeper. If so, right-click the app → **Open**.
4. (Optional) **File → Install "Print to Purple PDF"…** registers a virtual
   PDF printer shortcut (CUPS-based).

> Requires macOS 11 (Big Sur) or later. Universal binary — Apple Silicon
> and Intel both supported.

## Windows

1. Download `Purple PDF Setup 1.0.0.exe` from the Releases page.
2. Run the installer; choose per-user or per-machine.
3. After install, Purple PDF launches and registers itself as a `.pdf`
   file handler.

> Requires Windows 10 1809 or later, x64.

## Optional CLIs

Purple PDF works out-of-the-box for read, annotate, sign, save, OCR,
watermark, header/footer, and crop. The features below additionally need
a CLI on `PATH`; absent CLIs surface an install hint inside the relevant
menu item instead of failing silently.

| CLI | Unlocks | macOS install | Windows install |
| --- | --- | --- | --- |
| **LibreOffice** | Office ↔ PDF conversion | `brew install --cask libreoffice` | [libreoffice.org](https://www.libreoffice.org/) |
| **qpdf** | AES-256 encryption & permissions | `brew install qpdf` | `choco install qpdf` or [qpdf releases](https://github.com/qpdf/qpdf/releases) |
| **Ghostscript** | PDF/A, PDF/X, Optimize | `brew install ghostscript` | `choco install ghostscript` |

OCR (Tesseract), the bundled Unicode font, and the application icons are
already bundled. **No network access is required at runtime** for any
shipped feature.

## Build from Source

### Prerequisites
- Node.js ≥ 20
- Python ≥ 3.10 + Pillow (only if you rebuild the icon set from
  `build/make_icon.py`)
- For signed/notarized macOS builds: an Apple Developer ID certificate
  imported into the keychain, plus the `APPLE_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` env vars.
- For signed Windows builds: an EV / OV code-signing certificate plus the
  `WIN_CSC_LINK` / `WIN_CSC_KEY_PASSWORD` env vars.

### Steps
```sh
git clone https://github.com/bronty13/PhantomLives.git
cd PhantomLives/PurplePDF
npm install
bash scripts/install-git-hooks.sh        # optional: auto-version on commit
npm run typecheck
npm test
npm run dist:mac     # or dist:win
```

Signed-release artifacts end up in `dist/`. For day-to-day development on
macOS, use the PhantomLives-convention scripts at the subproject root —
`./build-app.sh` builds + installs into `/Applications/Purple PDF.app` +
relaunches in one shot; `./install.sh` re-installs the last-built bundle
without rebuilding. The legacy `scripts/install-and-launch.sh` is
preserved for compatibility and is a thin wrapper around the same flow.

## Upgrading

In-app: **Help → Check for Updates…** uses `electron-updater` to pull the
latest signed package from the GitHub release feed. Updates download in
the background; the user is prompted; install completes on next quit.

To opt out: set `PURPLE_PDF_DISABLE_AUTO_UPDATE=1` before launch.

## Uninstall

- **macOS**: drag `/Applications/Purple PDF.app` to the Trash. User data
  (recents, autosaves, crash reports) lives under
  `~/Library/Application Support/Purple PDF/`.
- **Windows**: Settings → Apps → Purple PDF → Uninstall. User data lives
  under `%APPDATA%\Purple PDF\`.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Gatekeeper refuses to open on macOS | Right-click → **Open** the first time, or run `xattr -d com.apple.quarantine "/Applications/Purple PDF.app"` |
| "qpdf not found" when protecting | Install qpdf via the table above |
| "LibreOffice not found" converting Office | Install LibreOffice |
| "Ghostscript not found" converting to PDF/A | Install Ghostscript |
| OCR fails | OCR is fully offline in 1.0.0; if it still fails, **Help → Show Crash Reports Folder** and file an issue |
| Update check silently fails | Run **Help → Check for Updates…** for the detailed error |
| Save fails with EPERM | Use **Save As** to a writable location |
