// Bundle verification — reads Molly's two-layer ZIP and asserts every
// claimed sha256 in hashes.json matches the re-hashed bytes. Pure module
// (no Tauri dep) so the contract can be exhaustively unit-tested.
//
// Outer ZIP layout (per Molly's bundle_zip.rs):
//   <UID>.zip
//   ├── <UID>-inner.zip          (deflate-compressed, MS-DOS epoch entries)
//   ├── manifest.json            (Phase 2+; missing on pre-PR bundles)
//   └── hashes.json              ({ bundleUid, innerZip{name,sha256,bytes}, files[{path,sha256}] })
//
// Inner ZIP layout:
//   ├── info.md                  (human summary)
//   ├── Molly.log                (build log — line-based KEY: VALUE)
//   ├── Audio/<file>             (Content bundles with audio description)
//   ├── Video/00001_<orig>.<ext> (Content/Custom, position-prefixed)
//   ├── Photos/00001_<orig>.<ext> (Content/Custom, position-prefixed)
//   └── FanSite/DD_NN_<orig>.<ext> (FanSite, day-and-position-prefixed)

use std::fs;
use std::io::{Cursor, Read};
use std::path::Path;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, thiserror::Error)]
pub enum BundleIoError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("hashes.json missing from outer ZIP")]
    MissingHashes,
    #[error("hashes.json malformed: {0}")]
    MalformedHashes(String),
    #[error("inner zip entry `{0}` not present in outer ZIP")]
    MissingInnerZip(String),
    #[error("inner zip sha mismatch: claimed={claimed} live={live}")]
    InnerHashMismatch { claimed: String, live: String },
    #[error("file `{path}` sha mismatch: claimed={claimed} live={live}")]
    FileHashMismatch { path: String, claimed: String, live: String },
    #[error("file `{0}` present in hashes.json but missing from inner zip")]
    InnerEntryMissing(String),
}

impl serde::Serialize for BundleIoError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HashesInnerZip {
    pub name: String,
    pub sha256: String,
    pub bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HashesFile {
    pub path: String,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HashesDoc {
    pub bundle_uid: String,
    pub inner_zip: HashesInnerZip,
    pub files: Vec<HashesFile>,
}

/// Result of a full verify pass. Owns the parsed hashes doc + the bytes
/// of info.md / Molly.log / manifest.json (if present) so callers don't
/// have to re-open the ZIP. Per-entry file metadata (size + sha) is in
/// `hashes.files` — used to populate the bundle_files table.
///
/// Carries the validated inner-zip bytes so the extract step in Phase
/// 1b doesn't have to re-open the outer file from disk.
#[derive(Debug)]
pub struct ValidatedBundle {
    pub hashes: HashesDoc,
    /// hex(sha256) of the entire outer ZIP file on disk.
    pub source_zip_sha256: String,
    pub info_md: String,
    pub molly_log: String,
    /// Phase-2+ contract: present when Molly published with the manifest PR.
    pub manifest_json: Option<String>,
    /// Per-file size pulled from the inner zip's central directory.
    /// Keyed on `in_zip_path`. (hashes.files doesn't carry size.)
    pub file_sizes: std::collections::BTreeMap<String, u64>,
    /// Raw inner-zip bytes for downstream extraction. Always populated.
    pub inner_zip_bytes: Vec<u8>,
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_lower(&hasher.finalize())
}

fn sha256_file(path: &Path) -> Result<String, BundleIoError> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 { break; }
        hasher.update(&buf[..n]);
    }
    Ok(hex_lower(&hasher.finalize()))
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

/// Public entry point. Opens the outer ZIP at `path`, verifies every
/// hash claimed in hashes.json, and returns the validated payload.
pub fn verify_outer_zip(path: &Path) -> Result<ValidatedBundle, BundleIoError> {
    let outer_bytes = fs::read(path)?;
    let source_zip_sha256 = sha256_hex(&outer_bytes);

    let cursor = Cursor::new(&outer_bytes);
    let mut outer = zip::ZipArchive::new(cursor)?;

    // ---- Read hashes.json ----
    let hashes_bytes = read_outer_entry(&mut outer, "hashes.json")?
        .ok_or(BundleIoError::MissingHashes)?;
    let hashes: HashesDoc = serde_json::from_slice(&hashes_bytes)
        .map_err(|e| BundleIoError::MalformedHashes(e.to_string()))?;

    // ---- Optional Phase 2+ manifest.json ----
    let manifest_json = read_outer_entry(&mut outer, "manifest.json")?
        .map(|b| String::from_utf8_lossy(&b).to_string());

    // ---- Read + verify inner zip ----
    let inner_bytes = read_outer_entry(&mut outer, &hashes.inner_zip.name)?
        .ok_or_else(|| BundleIoError::MissingInnerZip(hashes.inner_zip.name.clone()))?;
    let live_inner = sha256_hex(&inner_bytes);
    if live_inner != hashes.inner_zip.sha256 {
        return Err(BundleIoError::InnerHashMismatch {
            claimed: hashes.inner_zip.sha256.clone(),
            live: live_inner,
        });
    }

    // ---- Re-hash every file inside the inner zip + collect sizes + grab
    // info.md / Molly.log bytes.
    let inner_cursor = Cursor::new(&inner_bytes);
    let mut inner = zip::ZipArchive::new(inner_cursor)?;

    let mut info_md = String::new();
    let mut molly_log = String::new();
    let mut file_sizes: std::collections::BTreeMap<String, u64> =
        std::collections::BTreeMap::new();
    let mut entry_shas: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();

    for i in 0..inner.len() {
        let mut entry = inner.by_index(i)?;
        if !entry.is_file() { continue; }
        let name = entry.name().to_string();
        let mut bytes = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut bytes)?;
        let sha = sha256_hex(&bytes);
        file_sizes.insert(name.clone(), bytes.len() as u64);
        if name == "info.md" {
            info_md = String::from_utf8_lossy(&bytes).into_owned();
        }
        if name == "Molly.log" {
            molly_log = String::from_utf8_lossy(&bytes).into_owned();
        }
        entry_shas.insert(name, sha);
    }

    for hashes_file in &hashes.files {
        let Some(live) = entry_shas.get(&hashes_file.path) else {
            return Err(BundleIoError::InnerEntryMissing(hashes_file.path.clone()));
        };
        if *live != hashes_file.sha256 {
            return Err(BundleIoError::FileHashMismatch {
                path: hashes_file.path.clone(),
                claimed: hashes_file.sha256.clone(),
                live: live.clone(),
            });
        }
    }

    Ok(ValidatedBundle {
        hashes,
        source_zip_sha256,
        info_md,
        molly_log,
        manifest_json,
        file_sizes,
        inner_zip_bytes: inner_bytes,
    })
}

/// Hash the outer ZIP file on disk without verifying. Used when ingest
/// wants to record source_zip_sha256 even on a verify failure (so we
/// can dedup re-imports of the same broken file).
#[allow(dead_code)]
pub fn hash_outer_zip(path: &Path) -> Result<String, BundleIoError> {
    sha256_file(path)
}

/// Classify an inner-zip path into a `kind` discriminator. Drives the
/// `bundle_files.kind` CHECK column.
pub fn classify_kind(in_zip_path: &str) -> &'static str {
    match in_zip_path {
        "info.md" => "info",
        "Molly.log" => "log",
        "manifest.json" => "manifest",
        _ => {
            if in_zip_path.starts_with("Video/") { return "video"; }
            if in_zip_path.starts_with("Photos/") { return "image"; }
            if in_zip_path.starts_with("Audio/") { return "audio"; }
            if in_zip_path.starts_with("FanSite/") {
                // Naive extension check; only video extensions Molly is
                // known to publish — everything else is image.
                let lower = in_zip_path.to_lowercase();
                if lower.ends_with(".mp4") || lower.ends_with(".mov")
                    || lower.ends_with(".m4v") || lower.ends_with(".webm")
                {
                    return "video";
                }
                return "image";
            }
            "other"
        }
    }
}

/// Parse `Video/00001_clip.mp4` or `Photos/00001_pic.jpg` into
/// (position, original_name). Returns (0, name-as-is) on parse failure.
pub fn parse_content_prefix(in_zip_path: &str) -> (i64, String) {
    let stripped = in_zip_path
        .strip_prefix("Video/")
        .or_else(|| in_zip_path.strip_prefix("Photos/"))
        .or_else(|| in_zip_path.strip_prefix("Audio/"))
        .unwrap_or(in_zip_path);
    if let Some((pos_str, rest)) = stripped.split_once('_') {
        if let Ok(pos) = pos_str.parse::<i64>() {
            return (pos, rest.to_string());
        }
    }
    (0, stripped.to_string())
}

/// Parse `FanSite/DD_NN_original.ext` into (day, position, original_name).
/// Returns (None, 0, name-as-is) on parse failure.
pub fn parse_fansite_prefix(in_zip_path: &str) -> (Option<i64>, i64, String) {
    let Some(stripped) = in_zip_path.strip_prefix("FanSite/") else {
        return (None, 0, in_zip_path.to_string());
    };
    let parts: Vec<&str> = stripped.splitn(3, '_').collect();
    if parts.len() == 3 {
        if let (Ok(day), Ok(pos)) = (parts[0].parse::<i64>(), parts[1].parse::<i64>()) {
            return (Some(day), pos, parts[2].to_string());
        }
    }
    (None, 0, stripped.to_string())
}

fn read_outer_entry(
    archive: &mut zip::ZipArchive<Cursor<&Vec<u8>>>,
    name: &str,
) -> Result<Option<Vec<u8>>, BundleIoError> {
    match archive.by_name(name) {
        Ok(mut entry) => {
            let mut bytes = Vec::with_capacity(entry.size() as usize);
            entry.read_to_end(&mut bytes)?;
            Ok(Some(bytes))
        }
        Err(zip::result::ZipError::FileNotFound) => Ok(None),
        Err(e) => Err(BundleIoError::Zip(e)),
    }
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

    /// Build a 2-layer Molly-style outer ZIP with deterministic content.
    /// Returns (outer-zip-bytes, expected-hashes-doc).
    fn build_fixture_zip(
        uid: &str,
        files: &[(&str, &[u8])],
    ) -> (Vec<u8>, HashesDoc) {
        // ---- inner zip ----
        let mut inner_buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut inner_buf);
            for (name, body) in files {
                zip.start_file(*name, opts()).unwrap();
                zip.write_all(body).unwrap();
            }
            zip.finish().unwrap();
        }
        let inner_bytes = inner_buf.into_inner();
        let inner_sha = sha256_hex(&inner_bytes);
        let inner_name = format!("{uid}-inner.zip");

        let hashes_files: Vec<HashesFile> = files
            .iter()
            .map(|(name, body)| HashesFile {
                path: name.to_string(),
                sha256: sha256_hex(body),
            })
            .collect();
        let hashes = HashesDoc {
            bundle_uid: uid.to_string(),
            inner_zip: HashesInnerZip {
                name: inner_name.clone(),
                sha256: inner_sha.clone(),
                bytes: inner_bytes.len() as u64,
            },
            files: hashes_files,
        };
        let hashes_json = serde_json::to_vec_pretty(&hashes).unwrap();

        // ---- outer zip ----
        let mut outer_buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut outer_buf);
            zip.start_file(&inner_name, opts()).unwrap();
            zip.write_all(&inner_bytes).unwrap();
            zip.start_file("hashes.json", opts()).unwrap();
            zip.write_all(&hashes_json).unwrap();
            zip.finish().unwrap();
        }
        (outer_buf.into_inner(), hashes)
    }

    fn write_outer(dir: &TempDir, name: &str, bytes: &[u8]) -> std::path::PathBuf {
        let p = dir.path().join(name);
        fs::write(&p, bytes).unwrap();
        p
    }

    #[test]
    fn happy_path_round_trips() {
        let dir = TempDir::new().unwrap();
        let (outer, hashes) = build_fixture_zip(
            "2026-05-22-0001",
            &[
                ("info.md", b"# Test\n"),
                ("Molly.log", b"Bundle UID: 2026-05-22-0001\n"),
                ("Photos/00001_a.jpg", b"PNG-bytes-A"),
                ("Video/00001_clip.mp4", b"MP4-bytes-V"),
            ],
        );
        let p = write_outer(&dir, "2026-05-22-0001.zip", &outer);
        let v = verify_outer_zip(&p).expect("verify ok");
        assert_eq!(v.hashes.bundle_uid, "2026-05-22-0001");
        assert_eq!(v.hashes.files.len(), 4);
        assert!(v.info_md.contains("Test"));
        assert!(v.molly_log.contains("Bundle UID"));
        assert!(v.manifest_json.is_none(), "pre-PR bundle: no manifest.json");
        assert_eq!(v.file_sizes.get("Photos/00001_a.jpg"), Some(&11));
        // Inner-zip sha + outer sha both populated.
        assert_eq!(v.hashes.inner_zip.sha256, hashes.inner_zip.sha256);
        assert_eq!(v.source_zip_sha256.len(), 64);
    }

    #[test]
    fn mismatched_inner_hash_is_caught() {
        let dir = TempDir::new().unwrap();
        let (mut outer, _hashes) = build_fixture_zip(
            "x",
            &[("info.md", b"# T\n"), ("Molly.log", b"L\n")],
        );
        // Corrupt one byte in the inner zip blob inside the outer.
        // Cheap approximation: flip the last byte (which is inside
        // either the inner.zip data or hashes.json data segment of the
        // outer central directory). To stay deterministic across zip
        // crate versions, instead we rebuild the fixture with a wrong
        // sha in hashes.json.
        // — easier: rebuild with bad-hash hashes.json directly.
        outer.clear();
        let (good_outer, good) = build_fixture_zip("x", &[("info.md", b"# T\n")]);
        let mut bad = good.clone();
        bad.inner_zip.sha256 = "0".repeat(64);
        let bad_json = serde_json::to_vec_pretty(&bad).unwrap();
        // Re-build outer with the same inner zip but corrupted hashes.json.
        let cur = Cursor::new(good_outer);
        let mut src = zip::ZipArchive::new(cur).unwrap();
        let mut inner_bytes = Vec::new();
        let inner_name;
        {
            let mut e = src.by_name(&good.inner_zip.name).unwrap();
            inner_name = e.name().to_string();
            e.read_to_end(&mut inner_bytes).unwrap();
        }
        let mut buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            zip.start_file(&inner_name, opts()).unwrap();
            zip.write_all(&inner_bytes).unwrap();
            zip.start_file("hashes.json", opts()).unwrap();
            zip.write_all(&bad_json).unwrap();
            zip.finish().unwrap();
        }
        let p = write_outer(&dir, "bad.zip", &buf.into_inner());
        let err = verify_outer_zip(&p).unwrap_err();
        assert!(
            matches!(err, BundleIoError::InnerHashMismatch { .. }),
            "expected InnerHashMismatch, got {err:?}",
        );
    }

    #[test]
    fn mismatched_file_hash_is_caught() {
        let dir = TempDir::new().unwrap();
        // Build with a known file, then rewrite hashes.json with the
        // wrong sha for that file.
        let (good_outer, mut hashes) = build_fixture_zip(
            "y",
            &[("info.md", b"# A\n"), ("Molly.log", b"L\n")],
        );
        // Corrupt the file entry's hash.
        hashes.files[0].sha256 = "deadbeef".repeat(8);
        let bad_json = serde_json::to_vec_pretty(&hashes).unwrap();

        // Re-construct outer with the corrupt hashes.json.
        let cur = Cursor::new(good_outer);
        let mut src = zip::ZipArchive::new(cur).unwrap();
        let mut inner_bytes = Vec::new();
        let inner_name;
        {
            let mut e = src.by_name(&hashes.inner_zip.name).unwrap();
            inner_name = e.name().to_string();
            e.read_to_end(&mut inner_bytes).unwrap();
        }
        let mut buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            zip.start_file(&inner_name, opts()).unwrap();
            zip.write_all(&inner_bytes).unwrap();
            zip.start_file("hashes.json", opts()).unwrap();
            zip.write_all(&bad_json).unwrap();
            zip.finish().unwrap();
        }
        let p = write_outer(&dir, "bad2.zip", &buf.into_inner());
        let err = verify_outer_zip(&p).unwrap_err();
        match err {
            BundleIoError::FileHashMismatch { path, .. } => {
                assert_eq!(path, "info.md");
            }
            other => panic!("expected FileHashMismatch, got {other:?}"),
        }
    }

    #[test]
    fn malformed_hashes_json_errors_cleanly() {
        let dir = TempDir::new().unwrap();
        let mut buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            zip.start_file("dummy-inner.zip", opts()).unwrap();
            zip.write_all(b"junk").unwrap();
            zip.start_file("hashes.json", opts()).unwrap();
            zip.write_all(b"{ not valid json }").unwrap();
            zip.finish().unwrap();
        }
        let p = write_outer(&dir, "malformed.zip", &buf.into_inner());
        let err = verify_outer_zip(&p).unwrap_err();
        assert!(matches!(err, BundleIoError::MalformedHashes(_)));
    }

    #[test]
    fn missing_hashes_json_errors_cleanly() {
        let dir = TempDir::new().unwrap();
        let mut buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            zip.start_file("anything.txt", opts()).unwrap();
            zip.write_all(b"x").unwrap();
            zip.finish().unwrap();
        }
        let p = write_outer(&dir, "no-hashes.zip", &buf.into_inner());
        let err = verify_outer_zip(&p).unwrap_err();
        assert!(matches!(err, BundleIoError::MissingHashes));
    }

    #[test]
    fn classify_kind_handles_every_layout() {
        assert_eq!(classify_kind("info.md"), "info");
        assert_eq!(classify_kind("Molly.log"), "log");
        assert_eq!(classify_kind("manifest.json"), "manifest");
        assert_eq!(classify_kind("Video/00001_clip.mp4"), "video");
        assert_eq!(classify_kind("Photos/00002_b.jpg"), "image");
        assert_eq!(classify_kind("Audio/desc.m4a"), "audio");
        assert_eq!(classify_kind("FanSite/06_01_a.mov"), "video");
        assert_eq!(classify_kind("FanSite/01_01_a.jpg"), "image");
        assert_eq!(classify_kind("random/file.txt"), "other");
    }

    #[test]
    fn parse_content_prefix_basic() {
        assert_eq!(parse_content_prefix("Video/00001_clip.mp4"), (1, "clip.mp4".to_string()));
        assert_eq!(parse_content_prefix("Photos/00042_pic.jpg"), (42, "pic.jpg".to_string()));
        assert_eq!(parse_content_prefix("Audio/00001_desc.m4a"), (1, "desc.m4a".to_string()));
        // Underscored original filenames must still parse correctly.
        assert_eq!(
            parse_content_prefix("Video/00007_my_clip_v2.mp4"),
            (7, "my_clip_v2.mp4".to_string()),
        );
    }

    #[test]
    fn parse_fansite_prefix_basic() {
        assert_eq!(
            parse_fansite_prefix("FanSite/01_01_IMG_3488.jpg"),
            (Some(1), 1, "IMG_3488.jpg".to_string()),
        );
        assert_eq!(
            parse_fansite_prefix("FanSite/15_03_clip.mov"),
            (Some(15), 3, "clip.mov".to_string()),
        );
        assert_eq!(parse_fansite_prefix("info.md"), (None, 0, "info.md".to_string()));
    }
}
