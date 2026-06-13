// Bundle manifest parsing — produces a single canonical `BundleManifest`
// struct from either source:
//
//   1. PREFERRED: `manifest.json` inside the outer ZIP (Phase 2+
//      contract — added by Molly's bundle_zip.rs `render_manifest_json`).
//   2. FALLBACK: `Molly.log` inside the inner ZIP (line-based KEY:VALUE
//      build log, written by every Molly version since v1.9.0). Used for
//      pre-PR bundles that don't carry manifest.json yet.
//
// The fallback path is the *critical path* until Phase 2 lands — both of
// Robert's existing bundles (2026-05-22-0002, 2026-05-23-0001) are pre-PR.
//
// Downstream consumers (Inbox listing, Bundle workspace Overview, the
// three Post Runners) only ever see `BundleManifest` — never the raw
// JSON or log text.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct FanDay {
    pub day_of_month: i64,
    pub message: String,
    pub file_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleManifest {
    pub uid: String,
    /// "content" | "custom" | "fansite"
    pub bundle_type: String,
    pub persona_code: Option<String>,
    pub title: String,
    pub content_date: Option<String>,
    pub go_live_date: Option<String>,
    pub special_instructions: String,

    // ---- Content-bundle fields ----
    /// "text" | "audio" | "none"
    pub description_mode: Option<String>,
    pub description_text: String,
    pub description_audio_path: Option<String>,
    pub categories: Vec<String>,

    // ---- Custom-bundle fields ----
    /// "site" | "url"
    pub delivery_kind: Option<String>,
    pub delivery_site_name: Option<String>,
    pub delivery_url: Option<String>,
    pub delivery_recipient: String,
    pub price_cents: Option<i64>,
    pub handled_in_platform: bool,

    // ---- FanSite-bundle fields ----
    pub fansite_year: Option<i64>,
    pub fansite_month: Option<i64>,
    pub fan_days: Vec<FanDay>,

    /// RFC3339-ish — what Molly stamped at publish time.
    pub published_at: Option<String>,

    // ---- Preview assets (Content + YouTube). Additive in manifest v1;
    // `#[serde(default)]` so bundles ingested before v0.27.3 (whose stored
    // manifest_json lacks these keys) still deserialize instead of collapsing
    // to a wiped Default. ----
    /// In-zip path of the selected cover/preview frame, or None.
    #[serde(default)]
    pub preview_thumbnail_path: Option<String>,
    #[serde(default)]
    pub preview_teaser_gif_path: Option<String>,

    // ---- YouTube-only visibility flags. None for non-YouTube bundles (and
    // for pre-v0.27.3 ingests). ----
    #[serde(default)]
    pub youtube_make_private: Option<bool>,
    /// Molly's "Also Post SFW ManyVids" choice for this YouTube bundle.
    #[serde(default)]
    pub youtube_also_post_sfw_manyvids: Option<bool>,
}

impl Default for BundleManifest {
    fn default() -> Self {
        Self {
            uid: String::new(),
            bundle_type: String::new(),
            persona_code: None,
            title: String::new(),
            content_date: None,
            go_live_date: None,
            special_instructions: String::new(),
            description_mode: None,
            description_text: String::new(),
            description_audio_path: None,
            categories: Vec::new(),
            delivery_kind: None,
            delivery_site_name: None,
            delivery_url: None,
            delivery_recipient: String::new(),
            price_cents: None,
            handled_in_platform: false,
            fansite_year: None,
            fansite_month: None,
            fan_days: Vec::new(),
            published_at: None,
            preview_thumbnail_path: None,
            preview_teaser_gif_path: None,
            youtube_make_private: None,
            youtube_also_post_sfw_manyvids: None,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ManifestError {
    #[error("manifest.json parse failed: {0}")]
    Json(String),
    #[error("Molly.log parse failed: missing required field `{0}`")]
    MissingLogField(&'static str),
}

impl serde::Serialize for ManifestError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---------------------------------------------------------------------------
// Phase 2+ path: manifest.json
// ---------------------------------------------------------------------------

/// PLAN.md §5 schema — mirror of what Molly's `render_manifest_json` emits.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonV1 {
    #[allow(dead_code)]
    manifest_version: Option<u32>,
    bundle_uid: String,
    bundle_type: String,
    persona_code: Option<String>,
    title: String,
    content_date: Option<String>,
    go_live_date: Option<String>,
    #[serde(default)]
    special_instructions: String,
    #[serde(default)]
    description: ManifestJsonDescription,
    #[serde(default)]
    preview: ManifestJsonPreview,
    #[serde(default)]
    categories: Vec<String>,
    #[serde(default)]
    delivery: ManifestJsonDelivery,
    #[serde(default)]
    fan_site: ManifestJsonFanSite,
    /// YouTube-only block; absent (None) for other bundle types.
    #[serde(default)]
    youtube: Option<ManifestJsonYouTube>,
    published_at: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonPreview {
    thumbnail_path: Option<String>,
    teaser_gif_path: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonYouTube {
    #[serde(default)]
    make_private: bool,
    #[serde(default)]
    also_post_sfw_manyvids: bool,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonDescription {
    mode: Option<String>,
    #[serde(default)]
    text: String,
    audio_path: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonDelivery {
    kind: Option<String>,
    site_name: Option<String>,
    url: Option<String>,
    #[serde(default)]
    recipient: String,
    price_cents: Option<i64>,
    #[serde(default)]
    handled_in_platform: bool,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonFanSite {
    year: Option<i64>,
    month: Option<i64>,
    #[serde(default)]
    days: Vec<ManifestJsonFanDay>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestJsonFanDay {
    day: i64,
    #[serde(default)]
    message: String,
    #[serde(default)]
    files: Vec<serde_json::Value>,
}

pub fn parse_manifest_json(raw: &str) -> Result<BundleManifest, ManifestError> {
    let doc: ManifestJsonV1 = serde_json::from_str(raw)
        .map_err(|e| ManifestError::Json(e.to_string()))?;
    Ok(BundleManifest {
        uid: doc.bundle_uid,
        bundle_type: doc.bundle_type,
        persona_code: doc.persona_code,
        title: doc.title,
        content_date: doc.content_date,
        go_live_date: doc.go_live_date,
        special_instructions: doc.special_instructions,
        description_mode: doc.description.mode,
        description_text: doc.description.text,
        description_audio_path: doc.description.audio_path,
        categories: doc.categories,
        delivery_kind: doc.delivery.kind,
        delivery_site_name: doc.delivery.site_name,
        delivery_url: doc.delivery.url,
        delivery_recipient: doc.delivery.recipient,
        price_cents: doc.delivery.price_cents,
        handled_in_platform: doc.delivery.handled_in_platform,
        fansite_year: doc.fan_site.year,
        fansite_month: doc.fan_site.month,
        fan_days: doc.fan_site.days.into_iter().map(|d| FanDay {
            day_of_month: d.day,
            file_count: d.files.len() as i64,
            message: d.message,
        }).collect(),
        published_at: doc.published_at,
        preview_thumbnail_path: doc.preview.thumbnail_path,
        preview_teaser_gif_path: doc.preview.teaser_gif_path,
        youtube_make_private: doc.youtube.as_ref().map(|y| y.make_private),
        youtube_also_post_sfw_manyvids: doc.youtube.as_ref().map(|y| y.also_post_sfw_manyvids),
    })
}

// ---------------------------------------------------------------------------
// Fallback path: Molly.log line-based KEY:VALUE
// ---------------------------------------------------------------------------

pub fn parse_molly_log(raw: &str) -> Result<BundleManifest, ManifestError> {
    let mut m = BundleManifest::default();
    let mut lines = raw.lines().peekable();

    // Two collector modes for multi-line continuations like
    //   Description text:
    //     | line 1
    //     | line 2
    // and
    //   Special instructions:
    //     | line 1
    let mut collect_into: Option<String> = None;
    let mut collected: Vec<String> = Vec::new();

    fn flush(target: Option<String>, lines: &mut Vec<String>, m: &mut BundleManifest) {
        let body = std::mem::take(lines).join("\n");
        match target.as_deref() {
            Some("description_text") => m.description_text = body,
            Some("special_instructions") => m.special_instructions = body,
            _ => {}
        }
    }

    while let Some(raw_line) = lines.next() {
        let line = raw_line.trim_end_matches('\r');

        // Continuation row for whichever multi-line buffer we're in.
        if let Some(continuation) = line.strip_prefix("  | ") {
            collected.push(continuation.to_string());
            continue;
        }
        // End of continuation: blank line or any non-`  | ` line.
        if collect_into.is_some() {
            flush(collect_into.take(), &mut collected, &mut m);
        }

        if let Some(v) = strip_key(line, "Bundle UID:") {
            m.uid = v.to_string();
            continue;
        }
        if let Some(v) = strip_key(line, "Bundle type:") {
            m.bundle_type = v.to_string();
            continue;
        }
        if let Some(v) = strip_key(line, "Persona:") {
            if v != "(unassigned)" { m.persona_code = Some(v.to_string()); }
            continue;
        }
        if let Some(v) = strip_key(line, "Generated:") {
            m.published_at = Some(v.to_string());
            continue;
        }
        if let Some(v) = strip_key(line, "Title:") {
            m.title = v.to_string();
            continue;
        }
        if let Some(v) = strip_key(line, "Content date:") {
            m.content_date = Some(v.to_string());
            continue;
        }
        if let Some(v) = strip_key(line, "Go-live date:") {
            m.go_live_date = Some(v.to_string());
            continue;
        }
        if let Some(v) = strip_key(line, "Description mode:") {
            let v = v.trim();
            if v != "(none)" { m.description_mode = Some(v.to_string()); }
            continue;
        }
        if let Some(v) = strip_key(line, "Description text:") {
            // Inline trailing text (Molly usually emits "" then `  | ...`).
            // If anything followed the colon on the same line, treat it
            // as a single-line body.
            if !v.is_empty() {
                m.description_text = v.to_string();
            } else {
                collect_into = Some("description_text".into());
            }
            continue;
        }
        if let Some(v) = strip_key(line, "Description audio:") {
            m.description_audio_path = Some(format!("Audio/{}", v.trim()));
            continue;
        }
        if line.starts_with("Categories (") && line.ends_with("):") {
            // Header — actual rows follow as `  1. CAT`.
            continue;
        }
        if let Some(cat) = parse_numbered_item(line) {
            m.categories.push(cat);
            continue;
        }
        if let Some(v) = strip_key(line, "Delivery recipient:") {
            m.delivery_recipient = v.to_string();
            continue;
        }
        if let Some(v) = strip_key(line, "Delivery platform:") {
            let v = v.trim();
            if v != "(not set)" {
                m.delivery_kind = Some("site".to_string());
                m.delivery_site_name = Some(v.to_string());
            }
            continue;
        }
        if let Some(v) = strip_key(line, "Delivery URL:") {
            m.delivery_kind = Some("url".to_string());
            m.delivery_url = Some(v.to_string());
            continue;
        }
        if let Some(v) = strip_key(line, "Price:") {
            parse_price(v.trim(), &mut m);
            continue;
        }
        if let Some(v) = strip_key(line, "Fan site month:") {
            // Format is "YYYY-MM" with extra trailing whitespace tolerated.
            let s = v.trim();
            if let Some((y, mo)) = s.split_once('-') {
                if let (Ok(y), Ok(mo)) = (y.parse::<i64>(), mo.parse::<i64>()) {
                    m.fansite_year = Some(y);
                    m.fansite_month = Some(mo);
                }
            }
            continue;
        }
        if line.starts_with("Days (") {
            // Header — `  Day NN (N files): message` lines follow.
            continue;
        }
        if let Some(day) = parse_fan_day_line(line) {
            m.fan_days.push(day);
            continue;
        }
        if line.starts_with("Special instructions:") {
            collect_into = Some("special_instructions".into());
            continue;
        }
    }
    // EOF: flush any trailing collector.
    if collect_into.is_some() {
        flush(collect_into.take(), &mut collected, &mut m);
    }

    // Required fields per the log contract.
    if m.uid.is_empty() {
        return Err(ManifestError::MissingLogField("Bundle UID"));
    }
    if m.bundle_type.is_empty() {
        return Err(ManifestError::MissingLogField("Bundle type"));
    }
    Ok(m)
}

fn strip_key<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(key)?;
    // Molly emits "Key:    value" — column-aligned. Drop arbitrary
    // leading whitespace and any trailing whitespace on the value.
    let trimmed = rest.trim_start_matches(|c: char| c.is_whitespace());
    Some(trimmed.trim_end())
}

/// Parse `  1. CAT_NAME` into `CAT_NAME`. Returns None for everything else.
fn parse_numbered_item(line: &str) -> Option<String> {
    let s = line.strip_prefix("  ")?;
    let (n, rest) = s.split_once(". ")?;
    n.parse::<i64>().ok()?;
    Some(rest.trim().to_string())
}

/// Parse `  Day 07 (2 files): message text` into FanDay.
fn parse_fan_day_line(line: &str) -> Option<FanDay> {
    let s = line.strip_prefix("  Day ")?;
    let (day_str, rest) = s.split_once(" (")?;
    let day: i64 = day_str.parse().ok()?;
    let (count_phrase, msg_with_prefix) = rest.split_once("): ")?;
    let file_count: i64 = count_phrase
        .split_whitespace()
        .next()?
        .parse()
        .ok()?;
    Some(FanDay {
        day_of_month: day,
        file_count,
        message: msg_with_prefix.trim().to_string(),
    })
}

fn parse_price(value: &str, m: &mut BundleManifest) {
    if value == "handled in delivery platform" {
        m.handled_in_platform = true;
        return;
    }
    if value == "(not set)" { return; }
    // Format Molly emits is `$<dollars>.<cents>` — strip $, parse.
    let v = value.trim_start_matches('$');
    let (d, c) = match v.split_once('.') {
        Some(t) => t,
        None => return,
    };
    let dollars: i64 = match d.parse() { Ok(x) => x, Err(_) => return };
    let cents: i64 = match c.parse() { Ok(x) => x, Err(_) => return };
    m.price_cents = Some(dollars * 100 + cents);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // Real fixture from Robert's bundle 2026-05-22-0002.zip — exactly the
    // header + INPUTS section + a few day rows. **Use a raw string so
    // leading whitespace on continuation/day lines is preserved exactly.**
    // (Escaped `\n\` + source-newline trims leading whitespace silently,
    // which corrupts `  Day NN` and `  | text` lines.)
    const FANSITE_LOG: &str = r#"================================================================
Molly Bundler — build log
================================================================
Bundle UID:         2026-05-22-0002
Bundle type:        fansite
Persona:            CoC
Generated:          2026-05-23T18:18:10.331535900+00:00

[INPUTS]
Title:              and before too soon it was JUNE
Content date:       2026-05-22
Fan site month:     2026-06
Days (30):
  Day 01 (2 files): and before too soon it was JUNE
  Day 02 (2 files): Clean Titty Tuesday Take ;)
  Day 06 (1 file): I can't even describe how good it feels
  Day 30 (1 file): I like the lace ... but does the lace like me?
Special instructions:
  (none)

[BUILD]
  info.md ... ...
"#;

    #[test]
    fn parse_fansite_log_basic() {
        let m = parse_molly_log(FANSITE_LOG).expect("parses");
        assert_eq!(m.uid, "2026-05-22-0002");
        assert_eq!(m.bundle_type, "fansite");
        assert_eq!(m.persona_code.as_deref(), Some("CoC"));
        assert_eq!(m.title, "and before too soon it was JUNE");
        assert_eq!(m.content_date.as_deref(), Some("2026-05-22"));
        assert_eq!(m.fansite_year, Some(2026));
        assert_eq!(m.fansite_month, Some(6));
        assert_eq!(m.fan_days.len(), 4);

        let d1 = &m.fan_days[0];
        assert_eq!(d1.day_of_month, 1);
        assert_eq!(d1.file_count, 2);
        assert_eq!(d1.message, "and before too soon it was JUNE");

        let d6 = &m.fan_days[2];
        assert_eq!(d6.day_of_month, 6);
        assert_eq!(d6.file_count, 1, "singular 'file' must parse");
        assert!(d6.message.contains("how good"));

        // No description_text / categories for fansite.
        assert!(m.categories.is_empty());
        assert_eq!(m.description_text, "");
        assert_eq!(m.published_at.as_deref(), Some("2026-05-23T18:18:10.331535900+00:00"));
    }

    const CONTENT_LOG: &str = r#"Bundle UID:         2026-05-22-0001
Bundle type:        content
Persona:            CoC
Generated:          2026-05-22T03:00:00Z

[INPUTS]
Title:              Mid-Month Drop
Content date:       2026-05-22
Go-live date:       2026-05-29
Description mode:   text
Description text:
  | Hello there
  | second line
Categories (3):
  1. BBW
  2. STUFFING
  3. SOLO
Special instructions:
  | be cute

[BUILD]
"#;

    #[test]
    fn parse_content_log_basic() {
        let m = parse_molly_log(CONTENT_LOG).expect("parses");
        assert_eq!(m.uid, "2026-05-22-0001");
        assert_eq!(m.bundle_type, "content");
        assert_eq!(m.title, "Mid-Month Drop");
        assert_eq!(m.go_live_date.as_deref(), Some("2026-05-29"));
        assert_eq!(m.description_mode.as_deref(), Some("text"));
        assert_eq!(m.description_text, "Hello there\nsecond line");
        assert_eq!(m.categories, vec!["BBW", "STUFFING", "SOLO"]);
        assert_eq!(m.special_instructions, "be cute");
        assert!(m.fan_days.is_empty());
    }

    const CUSTOM_LOG: &str = r#"Bundle UID:         2026-05-22-0014
Bundle type:        custom
Persona:            PoA
Generated:          2026-05-22T03:00:00Z

[INPUTS]
Title:              @username 5min custom
Content date:       2026-05-22
Delivery recipient: @username
Delivery platform:  C4S Studio messages
Price:              $49.00
Special instructions:
  (none)
"#;

    #[test]
    fn parse_custom_log_basic() {
        let m = parse_molly_log(CUSTOM_LOG).expect("parses");
        assert_eq!(m.bundle_type, "custom");
        assert_eq!(m.delivery_recipient, "@username");
        assert_eq!(m.delivery_kind.as_deref(), Some("site"));
        assert_eq!(m.delivery_site_name.as_deref(), Some("C4S Studio messages"));
        assert_eq!(m.price_cents, Some(4900));
        assert!(!m.handled_in_platform);
    }

    #[test]
    fn parse_custom_handled_in_platform() {
        let log = "Bundle UID: x\nBundle type: custom\nPrice:              handled in delivery platform\n";
        let m = parse_molly_log(log).expect("parses");
        assert!(m.handled_in_platform);
        assert!(m.price_cents.is_none());
    }

    #[test]
    fn parse_custom_url_delivery() {
        let log = "Bundle UID: x\nBundle type: custom\nDelivery URL:       https://example.com/custom\n";
        let m = parse_molly_log(log).expect("parses");
        assert_eq!(m.delivery_kind.as_deref(), Some("url"));
        assert_eq!(m.delivery_url.as_deref(), Some("https://example.com/custom"));
    }

    #[test]
    fn missing_required_field_errors() {
        // No `Bundle UID:` line — must error rather than silently make
        // a row with an empty uid (PRIMARY KEY conflict later).
        let log = "Title: nothing\nBundle type: content\n";
        assert!(matches!(
            parse_molly_log(log),
            Err(ManifestError::MissingLogField("Bundle UID"))
        ));
    }

    #[test]
    fn missing_bundle_type_errors() {
        let log = "Bundle UID: 2026-01-01-0001\n";
        assert!(matches!(
            parse_molly_log(log),
            Err(ManifestError::MissingLogField("Bundle type"))
        ));
    }

    const MANIFEST_JSON_V1: &str = r#"{
        "manifestVersion": 1,
        "bundleUid": "2026-05-22-0001",
        "bundleType": "content",
        "personaCode": "CoC",
        "title": "Mid-Month Drop",
        "contentDate": "2026-05-22",
        "goLiveDate": "2026-05-29",
        "specialInstructions": "be cute",
        "description": { "mode": "text", "text": "Hello there", "audioPath": null },
        "categories": ["BBW", "STUFFING", "SOLO"],
        "delivery": {
            "kind": null, "siteName": null, "url": null, "recipient": "",
            "priceCents": null, "handledInPlatform": false
        },
        "fanSite": { "year": null, "month": null, "days": [] },
        "files": [],
        "publishedAt": "2026-05-22T03:00:00Z"
    }"#;

    #[test]
    fn parse_manifest_json_v1() {
        let m = parse_manifest_json(MANIFEST_JSON_V1).expect("parses");
        assert_eq!(m.uid, "2026-05-22-0001");
        assert_eq!(m.bundle_type, "content");
        assert_eq!(m.title, "Mid-Month Drop");
        assert_eq!(m.categories.len(), 3);
        assert_eq!(m.description_mode.as_deref(), Some("text"));
        assert_eq!(m.published_at.as_deref(), Some("2026-05-22T03:00:00Z"));
    }

    #[test]
    fn parse_manifest_json_fansite() {
        let raw = r#"{
            "manifestVersion": 1, "bundleUid": "x", "bundleType": "fansite",
            "personaCode": "Sa", "title": "May", "contentDate": null, "goLiveDate": null,
            "specialInstructions": "",
            "description": {},
            "categories": [],
            "delivery": {},
            "fanSite": { "year": 2026, "month": 6, "days": [
                { "day": 1, "message": "hi", "files": [{}, {}] },
                { "day": 15, "message": "mid", "files": [{}] }
            ]},
            "publishedAt": null
        }"#;
        let m = parse_manifest_json(raw).expect("parses");
        assert_eq!(m.fansite_year, Some(2026));
        assert_eq!(m.fansite_month, Some(6));
        assert_eq!(m.fan_days.len(), 2);
        assert_eq!(m.fan_days[0].file_count, 2);
        assert_eq!(m.fan_days[1].day_of_month, 15);
    }

    #[test]
    fn manifest_json_malformed_errors() {
        let err = parse_manifest_json("{ not valid }").unwrap_err();
        assert!(matches!(err, ManifestError::Json(_)));
    }

    #[test]
    fn parse_manifest_json_youtube_preview_and_sfw() {
        let raw = r#"{
            "manifestVersion": 1, "bundleUid": "yt1", "bundleType": "youtube",
            "personaCode": "CoC", "title": "Tease", "contentDate": null,
            "goLiveDate": null, "specialInstructions": "",
            "description": { "mode": "text", "text": "watch me" },
            "preview": { "thumbnailPath": "Preview/thumbnail_2.jpg", "teaserGifPath": null },
            "categories": [], "delivery": {}, "fanSite": {},
            "youtube": { "makePrivate": true, "alsoPostSfwManyvids": true },
            "publishedAt": null
        }"#;
        let m = parse_manifest_json(raw).expect("parses");
        assert_eq!(m.preview_thumbnail_path.as_deref(), Some("Preview/thumbnail_2.jpg"));
        assert_eq!(m.preview_teaser_gif_path, None);
        assert_eq!(m.youtube_make_private, Some(true));
        assert_eq!(m.youtube_also_post_sfw_manyvids, Some(true));
    }

    #[test]
    fn parse_manifest_json_non_youtube_has_no_youtube_flags() {
        // A content bundle (no `youtube` block) leaves the flags None, but a
        // preview thumbnail still parses.
        let m = parse_manifest_json(MANIFEST_JSON_V1).expect("parses");
        assert_eq!(m.youtube_make_private, None);
        assert_eq!(m.youtube_also_post_sfw_manyvids, None);
    }

    #[test]
    fn bundle_manifest_deserializes_without_new_fields() {
        // A pre-v0.27.3 stored manifest_json (flat BundleManifest missing the
        // preview/youtube keys) must still round-trip via the detail path's
        // `serde_json::from_str`, not collapse to Default.
        let stored = r#"{
            "uid": "old1", "bundleType": "content", "personaCode": "CoC",
            "title": "Old", "contentDate": null, "goLiveDate": null,
            "specialInstructions": "", "descriptionMode": "text",
            "descriptionText": "hi", "descriptionAudioPath": null,
            "categories": [], "deliveryKind": null, "deliverySiteName": null,
            "deliveryUrl": null, "deliveryRecipient": "", "priceCents": null,
            "handledInPlatform": false, "fansiteYear": null, "fansiteMonth": null,
            "fanDays": [], "publishedAt": null
        }"#;
        let m: BundleManifest = serde_json::from_str(stored).expect("old manifest still deserializes");
        assert_eq!(m.title, "Old");
        assert_eq!(m.preview_thumbnail_path, None);
        assert_eq!(m.youtube_also_post_sfw_manyvids, None);
    }
}
