// Bundle extraction — given the inner ZIP bytes already validated by
// bundle_io::verify_outer_zip, pull every entry to `<work_root>/<UID>/`
// preserving the relative path layout (Audio/, Video/, Photos/, FanSite/,
// info.md, Molly.log).
//
// Idempotent: if `<target>/path` already exists with the expected size,
// skip the write. SHA recheck is intentionally NOT done — too expensive
// per-launch for bundles that may total hundreds of MB, and the hashes
// were already validated upstream during ingest.

use std::collections::BTreeMap;
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};

#[derive(Debug, thiserror::Error)]
pub enum ExtractError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip: {0}")]
    Zip(#[from] zip::result::ZipError),
}

/// Result of a single extract pass.
#[derive(Debug, Clone)]
pub struct ExtractedFile {
    pub in_zip_path: String,
    pub working_path: PathBuf,
    pub size_bytes: u64,
    /// True if the file was actually written this call. False = idempotent skip.
    pub written: bool,
}

/// Pure entry point. Reads the inner-zip bytes, extracts every file
/// inside to `<work_root>/<uid>/`, and returns one row per file. The
/// caller writes these to `bundle_files.working_path`.
///
/// `expected_sizes` is the size map ValidatedBundle already carries —
/// used to skip already-extracted files without re-reading their bytes.
pub fn extract_inner_zip(
    inner_bytes: &[u8],
    work_root: &Path,
    uid: &str,
    expected_sizes: &BTreeMap<String, u64>,
) -> Result<Vec<ExtractedFile>, ExtractError> {
    let bundle_dir = work_root.join(uid);
    fs::create_dir_all(&bundle_dir)?;

    let cursor = Cursor::new(inner_bytes);
    let mut archive = zip::ZipArchive::new(cursor)?;

    let mut out = Vec::with_capacity(archive.len());
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        if !entry.is_file() {
            // Inner zip is flat-ish; if a future Molly version adds
            // explicit directory entries we just mkdir them.
            if let Some(name) = entry.enclosed_name() {
                let dir = bundle_dir.join(name);
                fs::create_dir_all(&dir)?;
            }
            continue;
        }
        let in_zip_path = entry.name().to_string();
        let Some(rel) = entry.enclosed_name() else {
            // Hostile path (e.g. ../../etc/passwd); skip. ZIP itself
            // disallows this via enclosed_name() returning None.
            continue;
        };
        let target = bundle_dir.join(rel);

        let expected = expected_sizes.get(&in_zip_path).copied().unwrap_or(entry.size());
        if let Ok(meta) = fs::metadata(&target) {
            if meta.is_file() && meta.len() == expected {
                out.push(ExtractedFile {
                    in_zip_path,
                    working_path: target,
                    size_bytes: expected,
                    written: false,
                });
                continue;
            }
        }

        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        // Stream copy to disk via an atomic tmp-then-rename so a crash
        // mid-extract leaves the previous file (if any) intact.
        let tmp = target.with_extension(format!(
            "{}.sm-tmp",
            target.extension().and_then(|s| s.to_str()).unwrap_or("")
        ));
        {
            let mut out_file = fs::File::create(&tmp)?;
            let mut buf = [0u8; 64 * 1024];
            loop {
                let n = entry.read(&mut buf)?;
                if n == 0 { break; }
                std::io::Write::write_all(&mut out_file, &buf[..n])?;
            }
        }
        if target.exists() { let _ = fs::remove_file(&target); }
        fs::rename(&tmp, &target)?;

        out.push(ExtractedFile {
            in_zip_path,
            working_path: target,
            size_bytes: expected,
            written: true,
        });
    }

    Ok(out)
}

/// Resolve the per-bundle workspace directory. Public so commands like
/// `reveal_working_dir` and Phase 3+ ops can locate the extract root.
pub fn bundle_workspace_dir(work_root: &Path, uid: &str) -> PathBuf {
    work_root.join(uid)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::TempDir;
    use zip::write::SimpleFileOptions;

    fn opts() -> SimpleFileOptions {
        SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .last_modified_time(zip::DateTime::default())
            .unix_permissions(0o644)
    }

    fn fixture_inner_zip(files: &[(&str, &[u8])]) -> (Vec<u8>, BTreeMap<String, u64>) {
        let mut buf = Cursor::new(Vec::new());
        let mut sizes = BTreeMap::new();
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            for (name, body) in files {
                zip.start_file(*name, opts()).unwrap();
                zip.write_all(body).unwrap();
                sizes.insert(name.to_string(), body.len() as u64);
            }
            zip.finish().unwrap();
        }
        (buf.into_inner(), sizes)
    }

    #[test]
    fn fresh_extract_writes_every_file() {
        let dir = TempDir::new().unwrap();
        let (bytes, sizes) = fixture_inner_zip(&[
            ("info.md", b"# Hi\n"),
            ("Molly.log", b"Bundle UID: t\n"),
            ("FanSite/01_01_a.jpg", b"PNG-A"),
            ("FanSite/15_03_b.mov", b"MOV-B-bytes"),
        ]);
        let rows = extract_inner_zip(&bytes, dir.path(), "t", &sizes).unwrap();
        assert_eq!(rows.len(), 4);
        for row in &rows {
            assert!(row.written, "fresh extract should write each file");
            assert!(row.working_path.exists());
        }
        let target = dir.path().join("t").join("FanSite").join("01_01_a.jpg");
        assert_eq!(fs::read(&target).unwrap(), b"PNG-A");
    }

    #[test]
    fn re_extract_is_idempotent_no_op() {
        let dir = TempDir::new().unwrap();
        let (bytes, sizes) = fixture_inner_zip(&[
            ("info.md", b"# x\n"),
            ("Photos/00001_a.jpg", b"JPEG"),
        ]);
        let first = extract_inner_zip(&bytes, dir.path(), "u", &sizes).unwrap();
        for r in &first { assert!(r.written, "first pass writes"); }
        let second = extract_inner_zip(&bytes, dir.path(), "u", &sizes).unwrap();
        for r in &second {
            assert!(!r.written, "second pass is a no-op: {:?}", r.in_zip_path);
        }
    }

    #[test]
    fn partial_state_resumes_only_missing_files() {
        let dir = TempDir::new().unwrap();
        let (bytes, sizes) = fixture_inner_zip(&[
            ("info.md", b"# x\n"),
            ("FanSite/01_01_a.jpg", b"AAA"),
            ("FanSite/01_02_b.jpg", b"BBB"),
        ]);
        extract_inner_zip(&bytes, dir.path(), "v", &sizes).unwrap();
        // Wipe one of the extracted files.
        let victim = dir.path().join("v").join("FanSite").join("01_02_b.jpg");
        fs::remove_file(&victim).unwrap();
        let resume = extract_inner_zip(&bytes, dir.path(), "v", &sizes).unwrap();
        let written: Vec<_> = resume.iter().filter(|r| r.written).map(|r| r.in_zip_path.as_str()).collect();
        assert_eq!(written, vec!["FanSite/01_02_b.jpg"],
            "only the deleted file should be re-extracted");
        assert!(victim.exists());
    }

    #[test]
    fn size_mismatch_triggers_rewrite() {
        let dir = TempDir::new().unwrap();
        let (bytes, sizes) = fixture_inner_zip(&[
            ("info.md", b"# x\n"),
        ]);
        extract_inner_zip(&bytes, dir.path(), "w", &sizes).unwrap();
        // Corrupt the file with a different size.
        let target = dir.path().join("w").join("info.md");
        fs::write(&target, b"TOTALLY DIFFERENT BYTES").unwrap();
        let second = extract_inner_zip(&bytes, dir.path(), "w", &sizes).unwrap();
        assert!(second[0].written, "size mismatch should re-extract");
        assert_eq!(fs::read(&target).unwrap(), b"# x\n");
    }

    #[test]
    fn nested_dir_layout_preserved() {
        let dir = TempDir::new().unwrap();
        let (bytes, sizes) = fixture_inner_zip(&[
            ("Audio/desc.m4a", b"AAC"),
            ("Video/00007_clip_v2.mp4", b"MP4"),
            ("FanSite/30_03_picture.png", b"PNG"),
        ]);
        extract_inner_zip(&bytes, dir.path(), "x", &sizes).unwrap();
        assert!(dir.path().join("x/Audio/desc.m4a").exists());
        assert!(dir.path().join("x/Video/00007_clip_v2.mp4").exists());
        assert!(dir.path().join("x/FanSite/30_03_picture.png").exists());
    }

    #[test]
    fn workspace_dir_resolution() {
        let p = bundle_workspace_dir(Path::new("/work"), "2026-05-22-0002");
        assert_eq!(p.to_string_lossy(), "/work/2026-05-22-0002");
    }
}
