use std::path::{Path, PathBuf};

/// Resolve `~/Downloads/<sub>` cross-platform (Mac, Windows).
pub fn downloads_subdir(sub: &str) -> PathBuf {
    let base = dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(sub)
}

/// Open a path in the OS file browser (Finder on Mac, Explorer on Windows).
pub fn reveal_in_file_browser(path: &Path) -> std::io::Result<()> {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open").arg(path).status()?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer").arg(path).status()?;
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        std::process::Command::new("xdg-open").arg(path).status()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Whatever the host's Downloads dir resolution returns (or its
    /// fallback), the final path should end with the requested sub.
    /// Locks the contract that callers like `downloads_subdir("kinks.json")`
    /// can rely on for cross-platform behavior.
    #[test]
    fn downloads_subdir_resolves_with_sub() {
        let p = downloads_subdir("molly-test-sentinel.json");
        let s = p.to_string_lossy();
        assert!(
            s.ends_with("molly-test-sentinel.json"),
            "expected path to end with the sub; got {s}",
        );
        assert!(p.is_absolute() || s.starts_with('.'), "expected absolute or '.'-rooted path; got {s}");
    }
}
