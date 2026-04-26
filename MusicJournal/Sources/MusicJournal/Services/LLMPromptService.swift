// LLMPromptService.swift
// Per-track LLM round-trip via the system clipboard.
//
//  1. Render a user-customizable prompt template with the current track's
//     metadata, copy to the clipboard.
//  2. User pastes the prompt into Claude / ChatGPT / Gemini, copies the
//     LLM's JSON response back.
//  3. Parse the JSON and apply to the track's user-owned fields.
//
// The template lives in UserDefaults so the user can edit it in the LLM
// tab of Settings; falling back to `defaultTemplate` if unset.

import Foundation

/// Stateless helpers for the LLM clipboard round-trip.
enum LLMPromptService {

    // MARK: - Track template storage

    static let userDefaultsKey = "llmPromptTemplate"
    static let playlistDefaultsKey = "llmPlaylistPromptTemplate"

    // MARK: - Batch settings
    //
    // Chat LLM output is typically capped at 4–16k tokens — that's roughly
    // 50–80 detailed entries in our shape. Rather than tracking an indexed
    // cursor per playlist, we just take the next N tracks that don't yet
    // have an LLM-written `lyricSummary` or `userNotes`. Each round-trip
    // naturally picks up where the last one left off.

    static let batchSizeKey = "llmPlaylistBatchSize"
    static let defaultBatchSize = 50

    /// Max tracks per batch. Default 50.
    static var batchSize: Int {
        let v = UserDefaults.standard.integer(forKey: batchSizeKey)
        return v == 0 ? defaultBatchSize : v
    }

    static func setBatchSize(_ value: Int) {
        let clamped = max(5, min(500, value))
        UserDefaults.standard.set(clamped, forKey: batchSizeKey)
    }

    /// A track "needs annotation" when both `lyricSummary` and `userNotes`
    /// are empty. We deliberately ignore `lyrics` (per-track flow) and
    /// `songYear` (often filled by Spotify sync), so this only measures
    /// whether the *playlist-level* prompt has touched the row.
    static func tracksNeedingAnnotation(_ tracks: [Track]) -> [Track] {
        tracks.filter { $0.lyricSummary.isEmpty && $0.userNotes.isEmpty }
    }

    /// Default prompt — designed to coax a strict JSON response from any
    /// modern chat LLM. Uses `{{PLACEHOLDER}}` substitution.
    static let defaultTemplate = """
    I am annotating a song in my personal music journal. Here is the track:

    - Title: {{TRACK_NAME}}
    - Artist: {{ARTIST}}
    - Album: {{ALBUM}}
    - Year (from Spotify, may be the album's reissue year): {{YEAR}}
    - Duration: {{DURATION}}
    - Spotify: {{SPOTIFY_URL}}

    Please respond with ONLY a single JSON object — no commentary, no markdown code fences. Use these exact keys:

    {
      "songYear": <integer or null — the song's original release year if you know it, otherwise null>,
      "lyricSummary": "<2-3 sentence Markdown summary of the song's themes, mood, and meaning>",
      "lyrics": "<full song lyrics as plain text. Use blank lines between verses/choruses. Use empty string \\"\\" if you cannot reproduce them verbatim>",
      "notes": "<Markdown-formatted interesting facts: musical analysis, recording context, chart performance, cultural impact, related songs. 4-8 bullet points>"
    }

    All four keys must be present. Markdown is allowed inside the string values for lyricSummary and notes.

    CRITICAL: Inside any string value, when you want to quote a song title, album, lyric line, or short phrase, use SINGLE quotes — like 'American Pie' — NEVER double quotes. Unescaped double quotes inside JSON strings break the parser.
    """

    /// Returns the current template (custom or default).
    static var template: String {
        UserDefaults.standard.string(forKey: userDefaultsKey) ?? defaultTemplate
    }

    /// Stores a custom template, or removes the override when given the
    /// default verbatim or empty string.
    static func setTemplate(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultTemplate.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(value, forKey: userDefaultsKey)
        }
    }

    // MARK: - Render

    /// Substitutes track fields into the current template.
    static func render(for track: Track) -> String {
        var s = template
        s = s.replacingOccurrences(of: "{{TRACK_NAME}}", with: track.name)
        s = s.replacingOccurrences(of: "{{ARTIST}}", with: track.artistNames)
        s = s.replacingOccurrences(of: "{{ALBUM}}", with: track.albumName)
        s = s.replacingOccurrences(of: "{{YEAR}}", with: track.songYear.map(String.init) ?? "Unknown")
        s = s.replacingOccurrences(of: "{{DURATION}}", with: track.durationFormatted)
        s = s.replacingOccurrences(of: "{{SPOTIFY_URL}}", with: track.spotifyURL)
        return s
    }

    // MARK: - Response parsing

    /// Decoded shape of the LLM's JSON response. All fields optional so a
    /// partial response still applies what it can.
    struct Response: Decodable {
        let songYear: Int?
        let lyricSummary: String?
        let lyrics: String?
        let notes: String?
    }

    enum ParseError: LocalizedError {
        case empty
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Clipboard is empty. Copy the LLM's JSON response first."
            case .invalidJSON(let detail):
                return "Could not parse JSON: \(detail). Make sure you copied only the JSON object — no commentary or markdown fences."
            }
        }
    }

    /// Parses the LLM's clipboard text into a `Response`. Strips markdown
    /// code fences and, on strict-parse failure, attempts to repair the
    /// most common LLM mistake (unescaped double quotes inside string
    /// values) before re-trying.
    static func parseResponse(_ text: String) throws -> Response {
        let cleaned = stripCodeFences(text)
        guard !cleaned.isEmpty else { throw ParseError.empty }
        return try decodeWithRepair(cleaned, as: Response.self)
    }

    // MARK: - Playlist template

    /// Default playlist-level prompt. Lets the LLM update both the
    /// playlist's own notes/title and a batch of its tracks in one
    /// round-trip. Track entries are matched back by `spotifyId`.
    static let defaultPlaylistTemplate = """
    I am annotating a playlist in my personal music journal.

    Playlist: {{PLAYLIST_NAME}}
    Owner: {{OWNER}}
    Description: {{DESCRIPTION}}
    Total tracks in playlist: {{TOTAL_COUNT}}

    Below are {{BATCH_COUNT}} tracks I'd like you to annotate in this round (a subset of the full playlist; we'll process the rest in later rounds). Please annotate EVERY track in the list — don't pick favorites — keeping the spotifyId so I can match your response back:

    {{TRACK_LIST}}

    Please respond with ONLY a single JSON object — no commentary, no markdown code fences. Use these exact keys:

    {
      "playlistNotes": "<Markdown notes about this playlist as a whole — themes, vibe, era. 1-3 paragraphs. Use empty string if the playlist already has notes from a previous round>",
      "playlistTitle": "<optional custom title; empty string to leave alone>",
      "tracks": [
        {
          "spotifyId": "<must match exactly one of the IDs above>",
          "songYear": <integer or null>,
          "lyricSummary": "<2-3 sentence Markdown summary>",
          "notes": "<Markdown notes — facts, context, cultural impact>"
        }
      ]
    }

    Annotate every one of the {{BATCH_COUNT}} tracks listed above. Omit "lyrics" — too verbose at playlist scale; use the per-track prompt for those.

    CRITICAL: Inside any string value, when you want to quote a song title, album, lyric line, or short phrase, use SINGLE quotes — like 'American Pie' — NEVER double quotes. Unescaped double quotes inside JSON strings break the parser.
    """

    static var playlistTemplate: String {
        UserDefaults.standard.string(forKey: playlistDefaultsKey) ?? defaultPlaylistTemplate
    }

    static func setPlaylistTemplate(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty
            || trimmed == defaultPlaylistTemplate.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.removeObject(forKey: playlistDefaultsKey)
        } else {
            UserDefaults.standard.set(value, forKey: playlistDefaultsKey)
        }
    }

    /// Renders the playlist template for a batch of tracks. `batchTracks`
    /// is the slice the LLM should annotate (typically `batchSize`
    /// unannotated tracks); `totalCount` is the size of the full playlist.
    static func renderPlaylist(_ playlist: Playlist, batchTracks: [Track], totalCount: Int) -> String {
        let lines = batchTracks.map { t -> String in
            let year = t.songYear.map { " (\($0))" } ?? ""
            return "- [\(t.spotifyId)] \(t.name) — \(t.artistNames) · \(t.albumName)\(year)"
        }
        let trackList = lines.joined(separator: "\n")

        var s = playlistTemplate
        s = s.replacingOccurrences(of: "{{PLAYLIST_NAME}}",
                                   with: playlist.userTitle.isEmpty ? playlist.name : playlist.userTitle)
        s = s.replacingOccurrences(of: "{{OWNER}}", with: playlist.ownerName)
        s = s.replacingOccurrences(of: "{{DESCRIPTION}}",
                                   with: playlist.description.isEmpty ? "(none)" : playlist.description)
        s = s.replacingOccurrences(of: "{{TOTAL_COUNT}}", with: String(totalCount))
        s = s.replacingOccurrences(of: "{{BATCH_COUNT}}", with: String(batchTracks.count))
        // Backwards-compat for templates that still use the old placeholder.
        s = s.replacingOccurrences(of: "{{TRACK_COUNT}}", with: String(batchTracks.count))
        s = s.replacingOccurrences(of: "{{TRACK_LIST}}", with: trackList)
        return s
    }

    /// Decoded shape for the playlist-level response.
    struct PlaylistResponse: Decodable {
        let playlistNotes: String?
        let playlistTitle: String?
        let tracks: [TrackUpdate]?

        struct TrackUpdate: Decodable {
            let spotifyId: String
            let songYear: Int?
            let lyricSummary: String?
            let lyrics: String?
            let notes: String?
        }
    }

    /// Parses an LLM playlist-level response from clipboard text. Same
    /// repair behaviour as `parseResponse`.
    static func parsePlaylistResponse(_ text: String) throws -> PlaylistResponse {
        let cleaned = stripCodeFences(text)
        guard !cleaned.isEmpty else { throw ParseError.empty }
        return try decodeWithRepair(cleaned, as: PlaylistResponse.self)
    }

    /// Tries strict JSON decoding first; on failure, repairs the most
    /// common LLM mistake (unescaped `"` inside string values) and retries.
    private static func decodeWithRepair<T: Decodable>(_ text: String, as: T.Type) throws -> T {
        let decoder = JSONDecoder()
        if let data = text.data(using: .utf8),
           let strict = try? decoder.decode(T.self, from: data) {
            return strict
        }
        let repaired = repairUnescapedQuotes(text)
        guard let data = repaired.data(using: .utf8) else {
            throw ParseError.empty
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ParseError.invalidJSON(error.localizedDescription)
        }
    }

    /// Heuristic: walk the text once, tracking whether we are inside a
    /// JSON string. If we encounter an unescaped `"` whose next non-space
    /// character is *not* a structural token (`,`, `:`, `}`, `]`), treat
    /// it as an internal quote and escape it. Handles the common LLM
    /// pattern of writing `"notes":""American Pie" is..."` (which is what
    /// breaks strict parsing).
    static func repairUnescapedQuotes(_ input: String) -> String {
        let chars = Array(input)
        var out: [Character] = []
        out.reserveCapacity(chars.count + 32)
        var inString = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if !inString {
                if c == "\"" { inString = true }
                out.append(c)
                i += 1
                continue
            }
            // inside a string
            if c == "\\", i + 1 < chars.count {
                // copy escape sequence verbatim
                out.append(c)
                out.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "\"" {
                // Decide: end of string, or unescaped internal quote?
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                let follow = j < chars.count ? chars[j] : Character(" ")
                if j >= chars.count || follow == "," || follow == ":" || follow == "}" || follow == "]" {
                    inString = false
                    out.append(c)
                } else {
                    // internal — escape
                    out.append("\\")
                    out.append(c)
                }
                i += 1
                continue
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Drop the opening fence line (e.g. ```json or just ```).
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            } else {
                s = String(s.dropFirst(3))
            }
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
