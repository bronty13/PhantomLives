use std::path::{Path, PathBuf};

/// Resolve `~/Downloads/<sub>` cross-platform (Mac, Windows).
pub fn downloads_subdir(sub: &str) -> PathBuf {
    let base = dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(sub)
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
