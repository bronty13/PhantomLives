use std::path::{Path, PathBuf};

/// Resolve `~/Downloads/<sub>` cross-platform (Mac, Windows).
pub fn downloads_subdir(sub: &str) -> PathBuf {
    let base = dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(sub)
}

/// Resolve the bundle's *uploaded* preview/cover image — the file Molly put
/// in the bundle's `Preview/` folder, as distinct from the 30 frames SideMolly
/// generates for the thumbnail grid.
///
/// Prefers the manifest's recorded in-zip path (`manifest_rel`, e.g.
/// `Preview/thumbnail_2.jpg`) when it resolves to a real file. Falls back to
/// scanning `<workspace>/Preview/` for the first image — so bundles ingested
/// before the manifest carried `previewThumbnailPath` still work without a
/// re-ingest (the file was always extracted; only the manifest pointer was
/// missing). Returns None when the bundle has no preview image.
pub fn resolve_preview_image(workspace: &Path, manifest_rel: Option<&str>) -> Option<PathBuf> {
    if let Some(rel) = manifest_rel {
        let p = workspace.join(rel);
        if p.is_file() {
            return Some(p);
        }
    }
    let preview_dir = workspace.join("Preview");
    let mut images: Vec<PathBuf> = std::fs::read_dir(&preview_dir)
        .ok()?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_file() && is_image_ext(p))
        .collect();
    // Stable choice: alphabetical, so re-runs pick the same file.
    images.sort();
    images.into_iter().next()
}

fn is_image_ext(p: &Path) -> bool {
    matches!(
        p.extension().and_then(|e| e.to_str()).map(|s| s.to_ascii_lowercase()).as_deref(),
        Some("jpg" | "jpeg" | "png" | "webp" | "gif" | "heic" | "tiff" | "bmp")
    )
}

/// Show a path in the OS file browser (Finder on Mac, Explorer on Windows).
///
/// A **directory** is opened directly (the user lands inside the folder). A
/// **file** is *revealed* — selected in its containing folder — NOT opened.
/// This distinction is the v0.27.2 bug fix: plain `open <file>` on macOS
/// launches the file's default handler, and Parallels Desktop registers
/// itself as the handler for video extensions, so "Reveal" on the master
/// cut played the .mp4 inside Windows instead of showing it in Finder.
/// `open -R` (mac) / `explorer /select,` (win) select-without-opening.
pub fn reveal_in_file_browser(path: &Path) -> std::io::Result<()> {
    let (program, args) = reveal_command(path, path.is_dir());
    std::process::Command::new(program).args(&args).status()?;
    Ok(())
}

/// Build the `(program, args)` invocation for `reveal_in_file_browser`.
/// Pure + platform-branched so the file-vs-directory contract is unit
/// testable without actually launching Finder/Explorer.
fn reveal_command(path: &Path, is_dir: bool) -> (&'static str, Vec<String>) {
    let p = path.to_string_lossy().to_string();
    #[cfg(target_os = "macos")]
    {
        // `open -R` reveals & selects a file in Finder; a directory we just
        // open so the user lands inside it (the historical behavior).
        if is_dir { ("open", vec![p]) } else { ("open", vec!["-R".into(), p]) }
    }
    #[cfg(target_os = "windows")]
    {
        // `explorer /select,<file>` highlights the file in its folder;
        // a bare `explorer <dir>` opens the folder.
        if is_dir { ("explorer", vec![p]) } else { ("explorer", vec![format!("/select,{p}")]) }
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        // No portable "select" on Linux — reveal a file by opening its
        // parent directory; open a directory directly.
        if is_dir {
            ("xdg-open", vec![p])
        } else {
            let parent = path.parent().map(|x| x.to_string_lossy().to_string()).unwrap_or(p);
            ("xdg-open", vec![parent])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The v0.27.2 contract: files are *revealed* (selected), directories
    /// are *opened*. Regression guard against "Reveal" launching the file's
    /// default app (Parallels grabbing the .mp4 association).
    #[test]
    #[cfg(target_os = "macos")]
    fn reveal_command_selects_file_but_opens_dir() {
        let (prog_f, args_f) = reveal_command(Path::new("/tmp/a/master.mp4"), false);
        assert_eq!(prog_f, "open");
        assert_eq!(args_f, vec!["-R".to_string(), "/tmp/a/master.mp4".to_string()]);

        let (prog_d, args_d) = reveal_command(Path::new("/tmp/a"), true);
        assert_eq!(prog_d, "open");
        assert_eq!(args_d, vec!["/tmp/a".to_string()]); // no -R: open the folder
    }

    #[test]
    fn resolve_preview_prefers_manifest_then_falls_back_to_folder() {
        use std::fs;
        let base = std::env::temp_dir().join(format!("sm-preview-{}", std::process::id()));
        let preview = base.join("Preview");
        fs::create_dir_all(&preview).unwrap();
        // Manifest points at a real file → used verbatim.
        fs::write(preview.join("thumbnail_2.jpg"), b"x").unwrap();
        let got = resolve_preview_image(&base, Some("Preview/thumbnail_2.jpg")).unwrap();
        assert!(got.ends_with("Preview/thumbnail_2.jpg"));

        // Manifest path missing/stale → fall back to the single folder image,
        // even one with an odd name like Molly's "(1).jpg".
        fs::remove_file(preview.join("thumbnail_2.jpg")).unwrap();
        fs::write(preview.join("(1).jpg"), b"x").unwrap();
        let fallback = resolve_preview_image(&base, Some("Preview/gone.jpg")).unwrap();
        assert!(fallback.ends_with("(1).jpg"));
        // No manifest hint at all still finds it.
        let none_hint = resolve_preview_image(&base, None).unwrap();
        assert!(none_hint.ends_with("(1).jpg"));

        // Non-image files are ignored.
        fs::remove_file(preview.join("(1).jpg")).unwrap();
        fs::write(preview.join("notes.txt"), b"x").unwrap();
        assert!(resolve_preview_image(&base, None).is_none());
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn downloads_subdir_resolves_with_sub() {
        let p = downloads_subdir("sidemolly-test-sentinel.json");
        let s = p.to_string_lossy();
        assert!(
            s.ends_with("sidemolly-test-sentinel.json"),
            "expected path to end with the sub; got {s}",
        );
        assert!(p.is_absolute() || s.starts_with('.'), "expected absolute or '.'-rooted path; got {s}");
    }
}
