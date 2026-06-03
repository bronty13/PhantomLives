//! ffprobe wrapper: source dimensions, duration, HDR flag, audio presence.

use tauri::{AppHandle, Runtime};
use tokio::process::Command;

use crate::media::{ffmpeg_path, filters, MediaError};

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeResult {
    pub width: u32,
    pub height: u32,
    pub duration_sec: f64,
    pub is_hdr: bool,
    pub has_audio: bool,
    pub codec: String,
}

pub async fn probe<R: Runtime>(handle: &AppHandle<R>, path: &str) -> Result<ProbeResult, MediaError> {
    let bin = ffmpeg_path::ffprobe_bin(handle);
    let mut cmd = Command::new(&bin);
    cmd.args([
        "-v", "error",
        "-show_streams",
        "-show_format",
        "-of", "json",
        path,
    ]);
    crate::media::no_window(&mut cmd); // no console-window flash on Windows
    let out = cmd
        .output()
        .await
        .map_err(|e| MediaError::Probe(format!("spawn ffprobe: {e}")))?;
    if !out.status.success() {
        return Err(MediaError::Probe(
            String::from_utf8_lossy(&out.stderr).trim().to_string(),
        ));
    }
    let json: serde_json::Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| MediaError::Probe(format!("parse ffprobe json: {e}")))?;
    parse_probe(&json)
}

/// Pure parse of ffprobe `-show_streams -show_format -of json` output.
pub fn parse_probe(json: &serde_json::Value) -> Result<ProbeResult, MediaError> {
    let streams = json
        .get("streams")
        .and_then(|s| s.as_array())
        .ok_or_else(|| MediaError::Probe("no streams".into()))?;

    let video = streams
        .iter()
        .find(|s| s.get("codec_type").and_then(|v| v.as_str()) == Some("video"))
        .ok_or_else(|| MediaError::Probe("no video stream".into()))?;

    let width = video.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
    let height = video.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
    let codec = video
        .get("codec_name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let color_transfer = video
        .get("color_transfer")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let is_hdr = filters::is_hdr_transfer(color_transfer);

    let has_audio = streams
        .iter()
        .any(|s| s.get("codec_type").and_then(|v| v.as_str()) == Some("audio"));

    // Duration: prefer format.duration, fall back to the video stream's.
    let duration_sec = json
        .get("format")
        .and_then(|f| f.get("duration"))
        .and_then(|d| d.as_str())
        .or_else(|| video.get("duration").and_then(|d| d.as_str()))
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0);

    if width == 0 || height == 0 {
        return Err(MediaError::Probe("video stream has no dimensions".into()));
    }

    Ok(ProbeResult { width, height, duration_sec, is_hdr, has_audio, codec })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hevc_hdr_with_audio() {
        let j = serde_json::json!({
            "streams": [
                { "codec_type": "video", "codec_name": "hevc", "width": 3840, "height": 2160, "color_transfer": "arib-std-b67" },
                { "codec_type": "audio", "codec_name": "aac" }
            ],
            "format": { "duration": "12.530000" }
        });
        let r = parse_probe(&j).unwrap();
        assert_eq!((r.width, r.height), (3840, 2160));
        assert!(r.is_hdr);
        assert!(r.has_audio);
        assert_eq!(r.codec, "hevc");
        assert!((r.duration_sec - 12.53).abs() < 0.001);
    }

    #[test]
    fn parses_sdr_h264_no_audio() {
        let j = serde_json::json!({
            "streams": [
                { "codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080, "color_transfer": "bt709" }
            ],
            "format": { "duration": "5.0" }
        });
        let r = parse_probe(&j).unwrap();
        assert!(!r.is_hdr);
        assert!(!r.has_audio);
        assert_eq!(r.codec, "h264");
    }

    #[test]
    fn errors_without_video_stream() {
        let j = serde_json::json!({ "streams": [ { "codec_type": "audio" } ], "format": {} });
        assert!(parse_probe(&j).is_err());
    }
}
