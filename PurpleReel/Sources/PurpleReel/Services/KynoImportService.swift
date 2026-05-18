import Foundation

/// Best-effort importer for Kyno's `.LP_Store/` sidecar XML.
///
/// Kyno stores per-folder metadata inside a hidden `.LP_Store/`
/// directory next to the media (and historically `.kyno/`). The
/// exact schema isn't published but reverse-engineering yields a
/// stable subset: filename-keyed entries carrying rating, tags,
/// description, and (optionally) markers.
///
/// This importer is intentionally permissive — element names vary
/// slightly across Kyno versions, so it accepts the common
/// synonyms and silently skips anything it can't match against the
/// PurpleReel catalogue. The user is shown a summary count when
/// the run finishes.
///
/// We never write back to `.LP_Store/`; this is a one-way ingest.
@MainActor
enum KynoImportService {

    struct Result {
        var matched: Int = 0
        var clipFieldsApplied: Int = 0
        var ratingsApplied: Int = 0
        var tagsApplied: Int = 0
        var markersApplied: Int = 0
        var sidecarsFound: Int = 0
        var skipped: Int = 0
        /// Filenames in the sidecar XML that didn't match any
        /// asset currently in the PurpleReel catalogue. Surfaces in
        /// the result alert so the user can rescan the workspace
        /// first or move the missing files in.
        var unmatchedFilenames: [String] = []
    }

    /// Walk `root` (and every subdirectory) looking for `.LP_Store`
    /// folders. Parse the XML files inside each one and write the
    /// recovered metadata into PurpleReel's database for every
    /// matching catalogue asset. Returns a summary the caller can
    /// surface to the user.
    static func importTree(root: URL, db: DatabaseService) async -> Result {
        var result = Result()
        // Build a filename → asset index from the catalogue so we
        // can match O(1) without per-file SQL lookups.
        let assets = (try? db.allAssets()) ?? []
        let byName = Dictionary(grouping: assets, by: { $0.filename })

        let sidecars = await findSidecars(under: root)
        result.sidecarsFound = sidecars.count

        for xmlURL in sidecars {
            let entries = parseSidecar(at: xmlURL)
            for entry in entries {
                guard let candidates = byName[entry.filename],
                      let asset = candidates.first,
                      let aid = asset.rowId else {
                    result.unmatchedFilenames.append(entry.filename)
                    result.skipped += 1
                    continue
                }
                result.matched += 1
                apply(entry: entry, to: aid, db: db, result: &result)
            }
        }

        // De-dupe + cap the unmatched list at 50 to keep the alert
        // readable even on big workspaces.
        result.unmatchedFilenames = Array(
            Array(Set(result.unmatchedFilenames)).sorted().prefix(50)
        )
        return result
    }

    // MARK: - Filesystem walk

    /// Recursively enumerate `.LP_Store/*.xml` files under `root`.
    /// `.kyno/` is checked too for early-version exports. Detached
    /// so the (potentially deep) walk doesn't block the main actor.
    private static func findSidecars(under root: URL) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            var found: [URL] = []
            let fm = FileManager.default
            guard let walker = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return [] }
            // nextObject() instead of for-in to keep
            // skipDescendants() available under Swift 6 strict
            // concurrency (for-in on NSEnumerator tripped makeIterator).
            while let object = walker.nextObject() {
                guard let url = object as? URL else { continue }
                let name = url.lastPathComponent
                let parent = url.deletingLastPathComponent().lastPathComponent
                if (parent == ".LP_Store" || parent == ".kyno"),
                   url.pathExtension.lowercased() == "xml" {
                    found.append(url)
                }
                // Skip drilling into bundles / packages.
                if name.hasSuffix(".fcpbundle") || name.hasSuffix(".rdc") {
                    walker.skipDescendants()
                }
            }
            return found
        }.value
    }

    // MARK: - XML parsing

    /// Per-file record assembled from one `<asset>` (or equivalent)
    /// element inside a `.LP_Store` XML.
    fileprivate struct Entry {
        var filename: String
        var rating: Int? = nil
        var title: String? = nil
        var description: String? = nil
        var tags: [String] = []
        var markers: [(time: Double, note: String?)] = []
    }

    private static func parseSidecar(at url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let delegate = SidecarParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.entries
    }

    /// Permissive XMLParser delegate. Recognises a handful of
    /// element names per field so we work across Kyno's schema
    /// drift without locking to a single version.
    private final class SidecarParser: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        private var current: Entry?
        private var currentText: String = ""
        private var currentMarkerTime: Double?
        private var currentMarkerNote: String?

        func parser(_ parser: XMLParser,
                    didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            currentText = ""
            switch elementName.lowercased() {
            case "asset", "clip", "file", "media":
                // `filename` is on the element either as an attribute
                // or as a child element; capture either form.
                if let fn = attributeDict["filename"]
                       ?? attributeDict["name"]
                       ?? attributeDict["file"] {
                    current = Entry(filename: fn)
                } else {
                    current = Entry(filename: "")
                }
            case "marker":
                if let t = attributeDict["time"].flatMap(Double.init)
                    ?? attributeDict["timecode"].flatMap(Double.init)
                    ?? attributeDict["start"].flatMap(Double.init) {
                    currentMarkerTime = t
                }
                if let n = attributeDict["note"]
                       ?? attributeDict["text"]
                       ?? attributeDict["comment"] {
                    currentMarkerNote = n
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser,
                    didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentText = ""
            switch elementName.lowercased() {
            // Note: `"file"` lives in the asset-container case below
            // — it's a synonym for `<asset>` / `<clip>` per Kyno's
            // schema drift. Inner filename text is captured via the
            // `<filename>` / `<name>` synonyms here.
            case "filename", "name":
                if current?.filename.isEmpty == true, !text.isEmpty {
                    current?.filename = text
                }
            case "rating", "stars":
                if let r = Int(text) { current?.rating = max(0, min(5, r)) }
            case "title":
                current?.title = text.isEmpty ? nil : text
            case "description", "comment", "notes":
                current?.description = text.isEmpty ? nil : text
            case "tag", "keyword":
                if !text.isEmpty { current?.tags.append(text) }
            case "marker":
                if let t = currentMarkerTime, current != nil {
                    let note = currentMarkerNote
                                ?? (text.isEmpty ? nil : text)
                    current?.markers.append((time: t, note: note))
                }
                currentMarkerTime = nil
                currentMarkerNote = nil
            case "asset", "clip", "file", "media":
                if let entry = current,
                   !entry.filename.isEmpty {
                    entries.append(entry)
                }
                current = nil
            default: break
            }
        }
    }

    // MARK: - DB write

    private static func apply(entry: Entry, to assetId: Int64,
                              db: DatabaseService, result: inout Result) {
        // clip_metadata: title + description fold in additively over
        // whatever the user has already typed.
        if entry.title != nil || entry.description != nil {
            var meta = (try? db.clipMetadata(assetId: assetId))
                       ?? ClipMetadata(assetId: assetId,
                                       title: nil, description: nil,
                                       reel: nil, scene: nil, shot: nil,
                                       take: nil, angle: nil, camera: nil)
            if meta.title?.isEmpty != false { meta.title = entry.title }
            if meta.description?.isEmpty != false { meta.description = entry.description }
            try? db.setClipMetadata(meta)
            result.clipFieldsApplied += 1
        }
        if let r = entry.rating, r > 0 {
            try? db.setRating(assetId: assetId, stars: r,
                              colorLabel: nil, description: nil)
            result.ratingsApplied += 1
        }
        for tag in entry.tags {
            _ = try? db.addTag(name: tag, assetId: assetId)
            result.tagsApplied += 1
        }
        for m in entry.markers {
            _ = try? db.addMarker(assetId: assetId,
                                  timecodeIn: m.time,
                                  timecodeOut: nil,
                                  note: m.note)
            result.markersApplied += 1
        }
    }
}
