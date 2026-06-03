//! Spawn ffmpeg, stream `-progress` from stdout into a fraction callback,
//! capture a stderr tail, and enforce a timeout. No shell — argv is passed as
//! a vector so paths with spaces are safe on Windows.

use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::Mutex;
use tokio::time::timeout;

use crate::media::MediaError;

/// Parse a `-progress` line, returning elapsed microseconds. ffmpeg emits both
/// `out_time_us=` and (confusingly) `out_time_ms=` which is also microseconds.
fn parse_out_time_us(line: &str) -> Option<f64> {
    let v = line.strip_prefix("out_time_us=").or_else(|| line.strip_prefix("out_time_ms="))?;
    let t = v.trim();
    if t == "N/A" {
        return None;
    }
    t.parse::<f64>().ok()
}

fn tail(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        return s.to_string();
    }
    let v: Vec<char> = s.chars().collect();
    v[v.len() - n..].iter().collect()
}

/// Run ffmpeg to completion. `total_dur_sec` (>0) lets us turn elapsed time
/// into a [0,1] fraction for `on_progress`. Kills the child on timeout.
pub async fn run_ffmpeg(
    bin: &Path,
    args: &[String],
    total_dur_sec: f64,
    timeout_secs: u64,
    mut on_progress: impl FnMut(f64),
) -> Result<(), MediaError> {
    let mut child = Command::new(bin)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => MediaError::BinaryMissing,
            _ => MediaError::Io(e),
        })?;

    let stdout = child.stdout.take().ok_or_else(|| MediaError::Probe("no stdout".into()))?;
    let stderr = child.stderr.take().ok_or_else(|| MediaError::Probe("no stderr".into()))?;

    // Drain stderr into a bounded tail buffer (errors surface on failure).
    let errbuf = Arc::new(Mutex::new(String::new()));
    let eb = errbuf.clone();
    let err_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let mut b = eb.lock().await;
            b.push_str(&line);
            b.push('\n');
            if b.len() > 4000 {
                *b = tail(&b, 2000);
            }
        }
    });

    let read_progress = async {
        let mut lines = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if total_dur_sec > 0.0 {
                if let Some(us) = parse_out_time_us(&line) {
                    on_progress((us / 1_000_000.0 / total_dur_sec).clamp(0.0, 1.0));
                }
            }
        }
    };

    let status = match timeout(Duration::from_secs(timeout_secs), async {
        read_progress.await;
        child.wait().await
    })
    .await
    {
        Ok(r) => r.map_err(MediaError::Io)?,
        Err(_) => {
            let _ = child.kill().await;
            err_task.abort();
            return Err(MediaError::Timeout(timeout_secs));
        }
    };

    let _ = err_task.await;

    if !status.success() {
        let msg = tail(&errbuf.lock().await, 800);
        return Err(MediaError::Ffmpeg { code: status.code().unwrap_or(-1), stderr: msg });
    }
    on_progress(1.0);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_progress_microseconds() {
        assert_eq!(parse_out_time_us("out_time_us=500000"), Some(500000.0));
        assert_eq!(parse_out_time_us("out_time_ms=1500000"), Some(1500000.0));
        assert_eq!(parse_out_time_us("out_time_us=N/A"), None);
        assert_eq!(parse_out_time_us("frame=12"), None);
        assert_eq!(parse_out_time_us("progress=end"), None);
    }

    #[test]
    fn tail_keeps_last_n_chars() {
        assert_eq!(tail("abcdef", 3), "def");
        assert_eq!(tail("ab", 5), "ab");
    }
}
