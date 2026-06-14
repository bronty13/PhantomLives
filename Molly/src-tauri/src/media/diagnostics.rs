//! One-click, copyable diagnostics for the bundled video engine.
//!
//! Sallie is non-technical and can't be asked to find files or read sizes, so
//! Molly inspects its own `ffmpeg.exe`/`ffprobe.exe` and produces a plain-text
//! report she copies and sends to Robert. It answers the questions we can't
//! ask her to check by hand:
//!   - are the binaries actually THERE, and how big (a 0-byte/truncated file is
//!     the `os error 193` "not a valid Win32 application" signature);
//!   - did security tooling or sync software TOUCH them — a Defender quarantine
//!     stub, a OneDrive cloud placeholder (reparse/offline attributes), or a
//!     Mark-of-the-Web download flag;
//!   - what they hash to, and whether they actually RUN (the real error, not a
//!     swallowed one);
//!   - which security products are registered on the machine.
//!
//! Pure-ish + best-effort: every probe degrades to a note rather than failing,
//! so the report is always produced.

use std::path::Path;
use std::time::{Duration, UNIX_EPOCH};

use tauri::{AppHandle, Runtime};

use crate::media::ffmpeg_path;

const SMALL_FILE_BYTES: u64 = 1_000_000; // a real ffmpeg/ffprobe is tens of MB

pub async fn report<R: Runtime>(handle: &AppHandle<R>) -> String {
    let mut s = String::new();
    s.push_str("Molly video engine diagnostics — copy this and send it to Robert\n");
    s.push_str(&format!(
        "app: Molly {}  ({} {})\n",
        handle.package_info().version,
        std::env::consts::OS,
        std::env::consts::ARCH,
    ));
    s.push_str(&format!("security products: {}\n", security_products().await));

    for (label, bin) in [
        ("ffmpeg", ffmpeg_path::ffmpeg_bin(handle)),
        ("ffprobe", ffmpeg_path::ffprobe_bin(handle)),
    ] {
        s.push_str(&format!("\n[{label}] {}\n", bin.display()));
        match std::fs::metadata(&bin) {
            Ok(m) => {
                let size = m.len();
                let warn = if size == 0 {
                    "  (!! EMPTY — this is the os error 193 cause)"
                } else if size < SMALL_FILE_BYTES {
                    "  (!! suspiciously small — likely truncated/stubbed)"
                } else {
                    ""
                };
                s.push_str(&format!("  present: yes   size: {size} bytes{warn}\n"));
                s.push_str(&format!("  PE header (MZ): {}\n", pe_header(&bin)));
                s.push_str(&format!("  sha256: {}\n", sha256(&bin).unwrap_or_else(|| "n/a".into())));
                s.push_str(&format!("  modified (epoch s): {}\n", modified_epoch(&m)));
                s.push_str(&format!("  attributes: {}\n", attributes(&bin)));
                s.push_str(&format!("  mark-of-the-web: {}\n", mark_of_the_web(&bin)));
            }
            Err(e) => {
                s.push_str(&format!("  present: NO ({e})\n"));
            }
        }
        s.push_str(&format!("  runs -version: {}\n", run_version(&bin).await));
    }

    s
}

/// First two bytes are the DOS "MZ" magic every Windows PE starts with. A file
/// that exists but lacks it is corrupt/truncated/not-an-exe → os error 193.
fn pe_header(path: &Path) -> &'static str {
    use std::io::Read;
    let mut buf = [0u8; 2];
    match std::fs::File::open(path).and_then(|mut f| f.read_exact(&mut buf).map(|_| buf)) {
        Ok(b) if &b == b"MZ" => "yes",
        Ok(_) => "NO (not a Windows executable)",
        Err(_) => "could not read",
    }
}

fn sha256(path: &Path) -> Option<String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    let mut f = std::fs::File::open(path).ok()?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    loop {
        let n = f.read(&mut buf).ok()?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Some(format!("{:x}", hasher.finalize()))
}

fn modified_epoch(m: &std::fs::Metadata) -> String {
    m.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|| "n/a".into())
}

/// Windows file attributes that reveal a sync/security product replaced the
/// real bytes with a stub: a OneDrive cloud placeholder (REPARSE/OFFLINE/
/// RECALL) or a sparse/quarantine artifact. On non-Windows this is N/A.
#[cfg(windows)]
fn attributes(path: &Path) -> String {
    use std::os::windows::fs::MetadataExt;
    let Ok(m) = std::fs::metadata(path) else {
        return "n/a".into();
    };
    let a = m.file_attributes();
    let mut flags: Vec<&str> = Vec::new();
    if a & 0x0000_0400 != 0 { flags.push("REPARSE_POINT (cloud/symlink stub)"); }
    if a & 0x0000_1000 != 0 { flags.push("OFFLINE (cloud-dehydrated)"); }
    if a & 0x0040_0000 != 0 { flags.push("RECALL_ON_DATA_ACCESS (cloud)"); }
    if a & 0x0004_0000 != 0 { flags.push("RECALL_ON_OPEN (cloud)"); }
    if a & 0x0000_0200 != 0 { flags.push("SPARSE_FILE"); }
    if flags.is_empty() {
        "normal".into()
    } else {
        format!("{} (!! touched by sync/security tooling)", flags.join(", "))
    }
}

#[cfg(not(windows))]
fn attributes(_path: &Path) -> String {
    "n/a (not Windows)".into()
}

/// Whether the file carries a Zone.Identifier ADS — Windows' "Mark of the Web"
/// stamped on files that came from the internet / an installer. Its presence
/// tells us a download/extract path wrote the file (and may have been screened).
#[cfg(windows)]
fn mark_of_the_web(path: &Path) -> String {
    let ads = format!("{}:Zone.Identifier", path.display());
    if std::fs::metadata(&ads).is_ok() {
        "present (came from the internet / installer)".into()
    } else {
        "none".into()
    }
}

#[cfg(not(windows))]
fn mark_of_the_web(_path: &Path) -> String {
    "n/a (not Windows)".into()
}

/// Actually run `<bin> -version` and report the first line, or the real spawn
/// error (this is where os error 193 surfaces verbatim).
async fn run_version(bin: &Path) -> String {
    let mut cmd = tokio::process::Command::new(bin);
    cmd.arg("-version");
    crate::media::no_window(&mut cmd);
    match tokio::time::timeout(Duration::from_secs(10), cmd.output()).await {
        Ok(Ok(o)) if o.status.success() => {
            let first = String::from_utf8_lossy(&o.stdout)
                .lines()
                .next()
                .unwrap_or("")
                .to_string();
            format!("yes — {first}")
        }
        Ok(Ok(o)) => format!("ran but exited {:?}", o.status.code()),
        Ok(Err(e)) => format!("NO — {e}"),
        Err(_) => "NO — timed out".into(),
    }
}

/// Registered antivirus/security products via Windows Security Center. Answers
/// "is some security tool involved" even when Defender is reported off.
#[cfg(windows)]
async fn security_products() -> String {
    let mut cmd = tokio::process::Command::new("powershell");
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct \
         -ErrorAction SilentlyContinue | Select-Object -ExpandProperty displayName",
    ]);
    crate::media::no_window(&mut cmd);
    match tokio::time::timeout(Duration::from_secs(8), cmd.output()).await {
        Ok(Ok(o)) => {
            let names: Vec<String> = String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect();
            if names.is_empty() {
                "none registered".into()
            } else {
                names.join(", ")
            }
        }
        _ => "could not query".into(),
    }
}

#[cfg(not(windows))]
async fn security_products() -> String {
    "n/a (not Windows)".into()
}
