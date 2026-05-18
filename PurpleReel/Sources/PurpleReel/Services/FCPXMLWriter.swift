import Foundation

/// Minimal-but-conformant FCPXML v1.10 writer. We emit:
///   - One `<format>` per unique frame rate observed in the export set.
///   - One `<asset>` per source file (deduped by path).
///   - One `<event>` containing one `<asset-clip>` per asset, with
///     nested `<marker>`, `<keyword>` (for tags), and `<rating>` elements.
///   - Subclips are emitted as additional `<asset-clip>`s with explicit
///     `start` and `duration` clipped to the subclip's in/out range.
///
/// We deliberately don't roll a full library/project hierarchy — FCP
/// happily ingests an event-only XML into the user's currently active
/// library. Keeps the writer tight and avoids the user having to manage
/// a fresh library on every import.
///
/// FCPXML reference:
/// https://developer.apple.com/documentation/professional-video-applications/fcpxml-reference
struct FCPXMLExportInput {
    let asset: Asset
    let markers: [Marker]
    let subclips: [Subclip]
    let tags: [Tag]
    let rating: Rating?
    /// Kyno-parity log fields (Title / Description / Reel / Scene /
    /// Shot / Take / Angle / Camera). When non-nil, each populated
    /// field becomes an FCPXML `<md key="…" value="…"/>` entry so the
    /// information lands in Final Cut Pro's metadata inspector.
    var clipMetadata: ClipMetadata? = nil
}

enum FCPXMLWriter {

    /// Stable resource IDs assigned in writer order: r1, r2, …
    private struct IDs {
        var nextN = 1
        var formats: [String: String] = [:]   // fpsKey → "rN"
        var assets:  [String: String] = [:]   // assetPath → "rN"
        mutating func nextID() -> String {
            defer { nextN += 1 }
            return "r\(nextN)"
        }
    }

    static func makeXML(eventName: String, items: [FCPXMLExportInput],
                        toolVersion: String) -> String {
        var ids = IDs()
        var resources = ""
        var clips = ""

        // First pass: register formats and assets, build the clip list.
        for item in items {
            let fps = item.asset.frameRate ?? 30
            let width = item.asset.widthPx ?? 1920
            let height = item.asset.heightPx ?? 1080
            let duration = item.asset.durationSeconds ?? 0

            let fmtKey = formatKey(fps: fps, w: width, h: height)
            let formatID: String
            if let existing = ids.formats[fmtKey] {
                formatID = existing
            } else {
                formatID = ids.nextID()
                ids.formats[fmtKey] = formatID
                resources += formatElement(id: formatID, fps: fps, w: width, h: height)
            }

            let assetID: String
            if let existing = ids.assets[item.asset.path] {
                assetID = existing
            } else {
                assetID = ids.nextID()
                ids.assets[item.asset.path] = assetID
                resources += assetElement(
                    id: assetID,
                    name: item.asset.filename,
                    path: item.asset.path,
                    duration: duration, fps: fps,
                    formatID: formatID,
                    hasAudio: true   // assume; FCP figures it out from the file
                )
            }

            clips += assetClipElement(
                assetRef: assetID, formatID: formatID,
                name: item.asset.filename,
                duration: duration, fps: fps,
                markers: item.markers,
                tags: item.tags,
                rating: item.rating,
                clipMetadata: item.clipMetadata
            )

            for sub in item.subclips {
                clips += subclipElement(
                    assetRef: assetID, formatID: formatID,
                    subclip: sub, fps: fps
                )
            }
        }

        var x = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        x += #"<!DOCTYPE fcpxml>"# + "\n"
        x += #"<fcpxml version="1.10">"# + "\n"
        x += "  <!-- Exported by PurpleReel \(escape(toolVersion)) -->\n"
        x += "  <resources>\n"
        x += resources
        x += "  </resources>\n"
        x += "  <event name=\"\(escape(eventName))\">\n"
        x += clips
        x += "  </event>\n"
        x += "</fcpxml>\n"
        return x
    }

    static func write(eventName: String,
                      items: [FCPXMLExportInput],
                      toolVersion: String,
                      to url: URL) throws {
        let xml = makeXML(eventName: eventName, items: items, toolVersion: toolVersion)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Element builders

    private static func formatElement(id: String, fps: Double, w: Int, h: Int) -> String {
        let (numerator, denominator, name) = frameDurationRational(fps: fps)
        return """
              <format id="\(id)" name="\(name)" frameDuration="\(numerator)/\(denominator)s" width="\(w)" height="\(h)"/>\n
            """
    }

    private static func assetElement(id: String, name: String, path: String,
                                      duration: Double, fps: Double,
                                      formatID: String, hasAudio: Bool) -> String {
        let dur = rationalTime(seconds: duration, fps: fps)
        let src = fileURL(path: path)
        var s = #"      <asset id="\#(id)" name="\#(escape(name))" "#
        s += #"hasVideo="1" "#
        s += hasAudio ? #"hasAudio="1" audioSources="1" audioChannels="2" audioRate="48000" "# : ""
        s += #"format="\#(formatID)" duration="\#(dur)" start="0s">"# + "\n"
        s += #"        <media-rep kind="original-media" src="\#(src)"/>"# + "\n"
        s += "      </asset>\n"
        return s
    }

    private static func assetClipElement(assetRef: String, formatID: String,
                                          name: String, duration: Double,
                                          fps: Double,
                                          markers: [Marker], tags: [Tag],
                                          rating: Rating?,
                                          clipMetadata: ClipMetadata? = nil) -> String {
        let dur = rationalTime(seconds: duration, fps: fps)
        var s = #"    <asset-clip ref="\#(assetRef)" name="\#(escape(name))" "#
        s += #"offset="0s" start="0s" duration="\#(dur)" format="\#(formatID)">"# + "\n"

        for marker in markers {
            let mStart = rationalTime(seconds: marker.timecodeIn, fps: fps)
            let mDur = rationalTime(seconds: 1.0 / fps, fps: fps)
            let note = marker.note ?? ""
            s += #"      <marker start="\#(mStart)" duration="\#(mDur)" value="\#(escape(note))"/>"# + "\n"
        }

        if !tags.isEmpty {
            let joined = tags.map { $0.name }.joined(separator: ", ")
            s += #"      <keyword start="0s" duration="\#(dur)" value="\#(escape(joined))"/>"# + "\n"
        }

        if let rating, rating.stars >= 4 {
            // FCP's rating system only has "favorite" (no star ratings);
            // map 4-5 stars to favorite, others to no rating.
            s += #"      <rating name="Favorite" start="0s" duration="\#(dur)" value="favorite"/>"# + "\n"
        }

        // Kyno log fields → FCPXML `<metadata>` block. FCP shows these
        // in the Info inspector under "Custom Metadata". Skip the
        // block entirely when nothing populated to keep XML tidy.
        if let m = clipMetadata {
            let fields: [(String, String?)] = [
                ("Title", m.title), ("Description", m.description),
                ("Reel", m.reel), ("Scene", m.scene),
                ("Shot", m.shot), ("Take", m.take),
                ("Angle", m.angle), ("Camera", m.camera),
            ]
            let present = fields.compactMap { (key, val) -> (String, String)? in
                guard let v = val, !v.isEmpty else { return nil }
                return (key, v)
            }
            if !present.isEmpty {
                s += "      <metadata>\n"
                for (key, val) in present {
                    s += #"        <md key="\#(escape(key))" value="\#(escape(val))"/>"# + "\n"
                }
                s += "      </metadata>\n"
            }
        }

        s += "    </asset-clip>\n"
        return s
    }

    private static func subclipElement(assetRef: String, formatID: String,
                                        subclip: Subclip, fps: Double) -> String {
        let start = rationalTime(seconds: subclip.timecodeIn, fps: fps)
        let dur = rationalTime(seconds: max(0, subclip.timecodeOut - subclip.timecodeIn), fps: fps)
        return """
            <asset-clip ref="\(assetRef)" name="\(escape(subclip.name))" offset="0s" start="\(start)" duration="\(dur)" format="\(formatID)"/>\n
        """
    }

    // MARK: - Time math

    /// Convert seconds to FCPXML rational time, snapped to the asset's
    /// frame grid for FCP-friendly playback. Returns a string like
    /// `"6006/30000s"`.
    private static func rationalTime(seconds: Double, fps: Double) -> String {
        let (numFD, denFD, _) = frameDurationRational(fps: fps)
        // total = round(seconds / (numFD/denFD)) * numFD
        let frames = Int((seconds * Double(denFD) / Double(numFD)).rounded())
        let numerator = frames * numFD
        return "\(numerator)/\(denFD)s"
    }

    /// Map common video frame rates to FCPXML rational frame durations
    /// and FCP's named format strings. Fallback for unknown rates uses
    /// the closest multiple of 1/(fps*1000).
    private static func frameDurationRational(fps: Double) -> (num: Int, den: Int, name: String) {
        // Snap to known rates within ±0.01 fps.
        let rates: [(fps: Double, num: Int, den: Int, name: String)] = [
            (23.976, 1001, 24000, "FFVideoFormat1080p2398"),
            (24.0,    100,  2400, "FFVideoFormat1080p24"),
            (25.0,    100,  2500, "FFVideoFormat1080p25"),
            (29.97,  1001, 30000, "FFVideoFormat1080p2997"),
            (30.0,    100,  3000, "FFVideoFormat1080p30"),
            (50.0,    100,  5000, "FFVideoFormat1080p50"),
            (59.94,  1001, 60000, "FFVideoFormat1080p5994"),
            (60.0,    100,  6000, "FFVideoFormat1080p60"),
        ]
        for r in rates where abs(r.fps - fps) < 0.01 {
            return (r.num, r.den, r.name)
        }
        // Fallback: rate * 1000 frames per 1000 seconds (less precise but valid).
        let denominator = Int((fps * 1000).rounded())
        return (1000, denominator, "FFVideoFormatRateUndefined")
    }

    // MARK: - String helpers

    private static func fileURL(path: String) -> String {
        // Percent-encode for URL validity, then XML-escape the result.
        // `.urlPathAllowed` permits `&`, which is a percent-encoding-
        // legal but XML-illegal character; without the second escape
        // the emitted FCPXML fails to parse for any path containing
        // an ampersand.
        let escapedPath = path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? path
        return escape("file://\(escapedPath)")
    }

    private static func formatKey(fps: Double, w: Int, h: Int) -> String {
        "\(Int(fps * 1000))_\(w)x\(h)"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
