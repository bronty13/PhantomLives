import Foundation

/// User-defined transcode presets live as individual JSON files in
/// `~/Library/Application Support/PurpleReel/CustomPresets/`. One file
/// per preset, named `<id>.json`. The format is whatever
/// `TranscodePreset`'s Codable conformance produces — round-trips
/// cleanly so an exported preset can be re-imported on another
/// machine.
///
/// We deliberately store one preset per file (rather than a single
/// catalog) so the user can hand-edit a file in TextEdit and share an
/// individual recipe without bundling the whole library.
enum CustomPresets {
    /// Resolve the custom-presets directory, creating it on first use.
    /// Failures (read-only volume, no Library directory) are logged
    /// and return nil — callers degrade to an empty custom set rather
    /// than crash the app.
    static func directory() -> URL? {
        let support = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/PurpleReel/CustomPresets")
        let url = URL(fileURLWithPath: support, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            return url
        } catch {
            NSLog("[PurpleReel] CustomPresets.directory() failed: \(error)")
            return nil
        }
    }

    /// Decode every `.json` file in the custom directory. Files that
    /// fail to parse are skipped (logged), so a single bad export
    /// can't break the rest of the user's library.
    static func load() -> [TranscodePreset] {
        guard let dir = directory() else { return [] }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var out: [TranscodePreset] = []
        let decoder = JSONDecoder()
        for url in entries where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let preset = try decoder.decode(TranscodePreset.self, from: data)
                out.append(preset)
            } catch {
                NSLog("[PurpleReel] CustomPresets: could not decode \(url.lastPathComponent): \(error)")
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Write a preset to the customs directory. The file name is
    /// derived from the preset id so re-saving overwrites cleanly.
    /// Returns the resolved URL or nil on failure.
    @discardableResult
    static func save(_ preset: TranscodePreset) -> URL? {
        guard let dir = directory() else { return nil }
        let url = dir.appendingPathComponent("\(preset.id).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preset)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("[PurpleReel] CustomPresets.save(\(preset.id)) failed: \(error)")
            return nil
        }
    }

    /// Delete a preset's JSON file. Refuses to touch built-in IDs —
    /// those have no on-disk file anyway, but this is a guardrail
    /// against UI bugs.
    static func delete(_ preset: TranscodePreset) {
        guard preset.isCustom, let dir = directory() else { return }
        let url = dir.appendingPathComponent("\(preset.id).json")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            NSLog("[PurpleReel] CustomPresets.delete(\(preset.id)) failed: \(error)")
        }
    }

    /// Parse a user-supplied `.json` and copy it into the customs
    /// directory. Used by the Settings "Import…" affordance.
    ///
    /// - Returns: the decoded preset on success, or throws so the UI
    ///   can surface a helpful alert.
    /// - Note: rejects imports whose id collides with a built-in to
    ///   keep the shortcut menu indices stable. Same-id collisions
    ///   with other customs are allowed and overwrite.
    @discardableResult
    static func `import`(from source: URL) throws -> TranscodePreset {
        let data = try Data(contentsOf: source)
        let preset = try JSONDecoder().decode(TranscodePreset.self, from: data)
        if TranscodePreset.builtInIDs.contains(preset.id) {
            throw NSError(
                domain: "PurpleReel.CustomPresets",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot import: '\(preset.id)' is a built-in preset id. Edit the JSON to use a unique id and try again."]
            )
        }
        guard save(preset) != nil else {
            throw NSError(
                domain: "PurpleReel.CustomPresets",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not write the preset to the customs directory."]
            )
        }
        return preset
    }

    /// Write the JSON for an arbitrary preset (built-in or custom) to
    /// `destination`. Used by the Settings "Export…" affordance so
    /// the user can share a built-in as a starting template.
    static func export(_ preset: TranscodePreset, to destination: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preset)
        try data.write(to: destination, options: .atomic)
    }
}
