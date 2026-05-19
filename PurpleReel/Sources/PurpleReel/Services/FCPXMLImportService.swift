import Foundation

/// FCPXML round-trip importer (Kyno-parity row 5).
///
/// The editor exports an FCPXML from Final Cut Pro (or Premiere
/// 2024+, which emits FCPXML 1.10) after they've added markers,
/// keywords, favorites, and log notes during the cut. We re-ingest
/// that XML and merge the changes back into the PurpleReel
/// catalogue — keying off the source file path inside the FCPXML
/// asset record so a renamed clip is still recognised.
///
/// Design notes:
///   - No new asset rows are ever created. If the FCPXML references
///     a file that PurpleReel doesn't know about, that clip's
///     metadata is reported as `unmatched` so the user can rescan
///     the workspace and re-run.
///   - Merge is additive. Markers are added with ±1/fps de-dupe
///     (same timecode + same note = skip). Keywords become tags,
///     deduped by name. Rating only ever goes up (FCP `favorite` →
///     5★; never demotes existing 4★+). Metadata fields fill empty
///     slots only — never overwrite.
///   - Marker time math respects FCPXML's rational time strings
///     (`"6006/30000s"`).
///   - Schema permissiveness: we accept v1.8 through v1.11 by
///     tolerating both `<asset-clip>` and `<clip>` containers and
///     looking up assets by attribute `ref`.
@MainActor
enum FCPXMLImportService {

    struct Result {
        var matchedClips: Int = 0
        var markersAdded: Int = 0
        var markersSkipped: Int = 0
        var tagsAdded: Int = 0
        var ratingsApplied: Int = 0
        var metadataFieldsApplied: Int = 0
        /// C25 — count of (asset, project) usage rows recorded in
        /// the catalogue this import. Sums new + refreshed rows;
        /// the DB upsert doesn't distinguish.
        var projectUsageRecorded: Int = 0
        /// Filenames the importer pulled out of the FCPXML but
        /// couldn't reconcile with a catalogue asset. Capped at 50
        /// for the alert.
        var unmatchedFilenames: [String] = []
    }

    /// Parse an FCPXML file and merge its metadata into the
    /// PurpleReel catalogue.
    static func importXML(at url: URL, db: DatabaseService) async -> Result {
        var result = Result()
        guard let data = try? Data(contentsOf: url) else { return result }

        // 1. Parse the XML into asset records + clip records.
        let parser = XMLParser(data: data)
        let delegate = FCPXMLParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()

        // 2. Build a (path → Asset) index so we can match.
        let assets = (try? db.allAssets()) ?? []
        let byPath = Dictionary(uniqueKeysWithValues:
            assets.map { ($0.path, $0) }
        )
        let byFilename = Dictionary(grouping: assets, by: { $0.filename })

        // 3. Walk each clip; resolve its asset ref; merge.
        for clip in delegate.clips {
            guard let assetRecord = delegate.assets[clip.assetRef] else { continue }
            let resolved = resolveAsset(
                record: assetRecord,
                byPath: byPath,
                byFilename: byFilename
            )
            guard let asset = resolved, let aid = asset.rowId else {
                result.unmatchedFilenames.append(assetRecord.filename)
                continue
            }
            result.matchedClips += 1
            merge(clip: clip,
                  intoAssetId: aid,
                  fps: asset.frameRate ?? 30,
                  db: db,
                  result: &result)
            // C25 — record project membership when the FCPXML's
            // surrounding `<project>` named the source. Skipped when
            // the clip was found outside any project (e.g. raw
            // event-level clip browse).
            if let projectName = clip.projectName, !projectName.isEmpty {
                do {
                    try db.recordFCPProjectUsage(
                        assetId: aid,
                        projectName: projectName,
                        eventName: clip.eventName,
                        libraryPath: url.path
                    )
                    result.projectUsageRecorded += 1
                } catch {
                    // Non-fatal — the rest of the import still
                    // succeeded. Log so a power user inspecting
                    // Console can see what broke.
                    NSLog("[PurpleReel] FCP project usage record failed: \(error)")
                }
            }
        }

        result.unmatchedFilenames = Array(
            Array(Set(result.unmatchedFilenames)).sorted().prefix(50)
        )
        return result
    }

    // MARK: - Asset resolution

    private static func resolveAsset(record: AssetRecord,
                                      byPath: [String: Asset],
                                      byFilename: [String: [Asset]]) -> Asset? {
        // 1. Try exact catalog path (URL-decoded).
        let decodedPath = record.path
            .removingPercentEncoding ?? record.path
        if let hit = byPath[decodedPath] { return hit }
        // 2. Try filename only. If multiple matches we don't know
        // which is canonical; surface as unmatched to keep merges
        // from landing on the wrong clip.
        let matches = byFilename[record.filename] ?? []
        if matches.count == 1 { return matches.first }
        return nil
    }

    // MARK: - Merge

    private static func merge(clip: ClipRecord,
                              intoAssetId aid: Int64,
                              fps: Double,
                              db: DatabaseService,
                              result: inout Result) {
        // -- Markers (additive, dedupe by timecode ± 1/fps + note) --
        let existing = (try? db.markers(assetId: aid)) ?? []
        let epsilon = max(0.05, 1.0 / max(fps, 1))
        for m in clip.markers {
            let dup = existing.contains { e in
                abs(e.timecodeIn - m.time) <= epsilon
                && (e.note ?? "") == (m.note ?? "")
            }
            if dup {
                result.markersSkipped += 1
                continue
            }
            _ = try? db.addMarker(assetId: aid,
                                  timecodeIn: m.time,
                                  timecodeOut: nil,
                                  note: m.note)
            result.markersAdded += 1
        }

        // -- Tags (dedupe by name; case-insensitive) --
        let existingTagNames = Set(
            ((try? db.tags(assetId: aid)) ?? []).map { $0.name.lowercased() }
        )
        for tag in clip.tags {
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !existingTagNames.contains(trimmed.lowercased())
            else { continue }
            _ = try? db.addTag(name: trimmed, assetId: aid)
            result.tagsAdded += 1
        }

        // -- Rating (only raise) --
        if clip.favorite {
            let current = (try? db.rating(assetId: aid))?.stars ?? 0
            if current < 5 {
                try? db.setRating(assetId: aid, stars: 5,
                                  colorLabel: nil, description: nil)
                result.ratingsApplied += 1
            }
        }

        // -- Clip metadata (fill empty slots only — never overwrite) --
        if !clip.metadata.isEmpty {
            var meta = (try? db.clipMetadata(assetId: aid))
                       ?? ClipMetadata(assetId: aid,
                                       title: nil, description: nil,
                                       reel: nil, scene: nil, shot: nil,
                                       take: nil, angle: nil, camera: nil)
            var changed = false
            func fill(_ key: String, into field: inout String?) {
                if (field ?? "").isEmpty,
                   let v = clip.metadata[key], !v.isEmpty {
                    field = v
                    changed = true
                    result.metadataFieldsApplied += 1
                }
            }
            fill("Title",       into: &meta.title)
            fill("Description", into: &meta.description)
            fill("Reel",        into: &meta.reel)
            fill("Scene",       into: &meta.scene)
            fill("Shot",        into: &meta.shot)
            fill("Take",        into: &meta.take)
            fill("Angle",       into: &meta.angle)
            fill("Camera",      into: &meta.camera)
            // FCP "Notes" field also lands in description if empty.
            if (meta.description ?? "").isEmpty,
               let note = clip.note, !note.isEmpty {
                meta.description = note
                changed = true
                result.metadataFieldsApplied += 1
            }
            if changed { try? db.setClipMetadata(meta) }
        }
    }
}

// MARK: - Parser types

/// A parsed `<asset>` (with its nested `<media-rep src=…/>`).
fileprivate struct AssetRecord {
    let id: String
    let filename: String
    /// Local filesystem path the source media resolves to. Derived
    /// from `media-rep`'s `src` attribute (a `file://` URL).
    let path: String
}

/// A parsed `<asset-clip>` / `<clip>` with the metadata it carries.
fileprivate struct ClipRecord {
    let assetRef: String
    var markers: [(time: Double, note: String?)] = []
    var tags: [String] = []
    var favorite: Bool = false
    var metadata: [String: String] = [:]
    var note: String? = nil
    /// C25 — name of the containing FCP `<project>` element (if
    /// any) and its `<event>` parent. Stamped at parse time from
    /// the enclosing-element stack so the importer can record
    /// (assetId, projectName) usage rows after the merge.
    var projectName: String? = nil
    var eventName: String? = nil
}

/// Permissive FCPXML 1.8-1.11 parser. We only care about the
/// asset/event/clip subtree that round-trips metadata; everything
/// else (timeline structure, transitions, audio mixing) is ignored.
fileprivate final class FCPXMLParser: NSObject, XMLParserDelegate {
    var assets: [String: AssetRecord] = [:]   // id → record
    var clips: [ClipRecord] = []

    private var currentAssetID: String?
    private var currentAssetName: String?
    private var currentAssetPath: String?
    private var currentClip: ClipRecord?
    /// Stack of nested clip-container elements (`<asset-clip>`,
    /// `<clip>`, `<mc-clip>`, `<sync-clip>`). We finalize the
    /// outermost one when the stack empties.
    private var clipStack: [ClipRecord] = []
    private var inMetadata: Bool = false
    private var noteText: String = ""
    private var inNote: Bool = false
    /// C25 — stack of the FCPXML event/project ancestors the parser
    /// is currently inside. The topmost name is stamped on each
    /// clip as it's finalized so the importer can record (assetId,
    /// projectName) usage rows. Both `<event>` and `<project>` push
    /// onto these stacks; we record the innermost name at clip
    /// finalize time. Cleared in the corresponding endElement.
    private var eventNameStack: [String] = []
    private var projectNameStack: [String] = []

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "asset":
            currentAssetID = attributeDict["id"]
            currentAssetName = attributeDict["name"]
            currentAssetPath = nil
        case "media-rep":
            // `src` is a `file://`-style URL. Decode percent escapes
            // to get a real path.
            if let src = attributeDict["src"] {
                if src.hasPrefix("file://") {
                    let stripped = String(src.dropFirst(7))
                    currentAssetPath = stripped.removingPercentEncoding ?? stripped
                } else {
                    currentAssetPath = src.removingPercentEncoding ?? src
                }
            }
        case "event":
            // C25 — track the FCPXML event name so we can stamp it on
            // contained clips. Pushed regardless of whether the event
            // has a name attribute (anonymous events are rare but
            // legal; we push "" so the pop balances).
            eventNameStack.append(attributeDict["name"] ?? "")
        case "project":
            projectNameStack.append(attributeDict["name"] ?? "")
        case "asset-clip", "clip", "mc-clip", "sync-clip":
            // Only `asset-clip` and the multi-cam variants carry a
            // `ref` directly. `<clip>` may also have a `ref` in
            // newer FCPXML versions.
            if let ref = attributeDict["ref"] {
                var record = ClipRecord(assetRef: ref)
                // C25 — stamp with the innermost project/event
                // context. Empty strings collapse to nil so the
                // DB row doesn't carry meaningless empty values.
                record.projectName = projectNameStack.last.flatMap {
                    $0.isEmpty ? nil : $0
                }
                record.eventName = eventNameStack.last.flatMap {
                    $0.isEmpty ? nil : $0
                }
                clipStack.append(record)
            }
        case "marker", "chapter-marker":
            // Always associate with the innermost clip container.
            guard !clipStack.isEmpty else { return }
            let t = parseRationalTime(attributeDict["start"]) ?? 0
            let value = attributeDict["value"]
            var top = clipStack.removeLast()
            top.markers.append((time: t, note: value))
            clipStack.append(top)
        case "keyword":
            guard !clipStack.isEmpty else { return }
            if let v = attributeDict["value"] {
                var top = clipStack.removeLast()
                // FCPXML keywords arrive comma-separated.
                top.tags.append(contentsOf:
                    v.split(separator: ",")
                     .map { String($0).trimmingCharacters(in: .whitespaces) }
                     .filter { !$0.isEmpty }
                )
                clipStack.append(top)
            }
        case "rating":
            guard !clipStack.isEmpty else { return }
            let val = attributeDict["value"] ?? ""
            let name = attributeDict["name"] ?? ""
            if val == "favorite" || name == "Favorite" {
                var top = clipStack.removeLast()
                top.favorite = true
                clipStack.append(top)
            }
        case "metadata":
            inMetadata = true
        case "md":
            guard inMetadata, !clipStack.isEmpty,
                  let key = attributeDict["key"],
                  let val = attributeDict["value"] else { return }
            var top = clipStack.removeLast()
            top.metadata[key] = val
            clipStack.append(top)
        case "note":
            inNote = true
            noteText = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inNote { noteText += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "asset":
            if let id = currentAssetID {
                assets[id] = AssetRecord(
                    id: id,
                    filename: currentAssetName
                                ?? (currentAssetPath.map {
                                    ($0 as NSString).lastPathComponent
                                } ?? ""),
                    path: currentAssetPath ?? ""
                )
            }
            currentAssetID = nil
            currentAssetName = nil
            currentAssetPath = nil
        case "asset-clip", "clip", "mc-clip", "sync-clip":
            if !clipStack.isEmpty {
                let finished = clipStack.removeLast()
                clips.append(finished)
            }
        case "event":
            if !eventNameStack.isEmpty { eventNameStack.removeLast() }
        case "project":
            if !projectNameStack.isEmpty { projectNameStack.removeLast() }
        case "metadata":
            inMetadata = false
        case "note":
            inNote = false
            let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !clipStack.isEmpty {
                var top = clipStack.removeLast()
                top.note = trimmed
                clipStack.append(top)
            }
            noteText = ""
        default: break
        }
    }

    /// Parse an FCPXML rational time string. Accepts:
    ///   - `"3600s"` (plain seconds)
    ///   - `"6006/30000s"` (numerator/denominator)
    ///   - `"0s"`
    /// Returns nil for anything else.
    private func parseRationalTime(_ raw: String?) -> Double? {
        guard let raw = raw else { return nil }
        guard raw.hasSuffix("s") else { return nil }
        let inner = String(raw.dropLast())
        if inner.contains("/") {
            let parts = inner.split(separator: "/", maxSplits: 1)
            if parts.count == 2,
               let num = Double(parts[0]),
               let den = Double(parts[1]),
               den != 0 {
                return num / den
            }
            return nil
        }
        return Double(inner)
    }
}
