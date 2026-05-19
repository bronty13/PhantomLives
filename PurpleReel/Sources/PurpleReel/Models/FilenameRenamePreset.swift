import Foundation

/// One named filename pattern shown in the Batch Rename dialog's
/// "File name pattern" Picker. Mirrors Kyno's Manage Filename
/// Presets list (Image #90): a row of system presets (locked, can't
/// edit / delete but Duplicate-able) plus an open-ended list of
/// user-created customs.
///
/// The `template` carries `${variable}` placeholders that
/// `BatchRenameService.expand(...)` resolves at render time. The
/// existing `{token}` syntax (PurpleReel pre-C10) continues to work
/// too — the engine accepts both forms.
struct FilenameRenamePreset: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var template: String
    /// System presets are locked — they ship with the app, can't be
    /// edited or deleted, but the user can Duplicate one to start a
    /// custom from a known-good shape.
    let isSystem: Bool
}

enum FilenameRenamePresetCatalog {

    /// Kyno-shaped system presets (Image #88). Templates use the
    /// `${variable}` syntax for forward-compat with the variable
    /// picker in `ManageFilenamePresetsSheet`. The engine also
    /// accepts the legacy `{token}` syntax for any pre-C10 templates
    /// users have saved under the `batchRenameTemplate` key.
    static let system: [FilenameRenamePreset] = [
        FilenameRenamePreset(
            id: "sys-add-prefix",
            name: "Add Prefix to Original Name",
            template: "${customName}${originalName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-add-suffix",
            name: "Add Suffix to Original Name",
            template: "${originalName}${customName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-custom",
            name: "Custom Name",
            template: "${customName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-custom-global-index",
            name: "Custom Name + Global Index",
            template: "${customName}_${globalIndex}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-custom-index",
            name: "Custom Name + Index",
            template: "${customName}_${index}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-custom-original",
            name: "Custom Name + Original Name",
            template: "${customName}_${originalName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-custom-timecode",
            name: "Custom Name + Timecode",
            template: "${customName}_${timecode}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original",
            name: "Original Name",
            template: "${originalName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original-custom",
            name: "Original Name + Custom Name",
            template: "${originalName}_${customName}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original-custom-index",
            name: "Original Name + Custom Name + Index",
            template: "${originalName}_${customName}_${index}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original-date",
            name: "Original Name + Date Modified",
            template: "${originalName}_${dateModified}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original-index",
            name: "Original Name + Index",
            template: "${originalName}_${index}${extension}",
            isSystem: true
        ),
        FilenameRenamePreset(
            id: "sys-original-timecode",
            name: "Original Name + Timecode",
            template: "${originalName}_${timecode}${extension}",
            isSystem: true
        ),
    ]
}

/// User-pattern persistence. User-created presets ride in the
/// standard `UserDefaults` under a single JSON-encoded key so the
/// list survives across launches without a separate file. System
/// presets stay in code; this enum only manages the deltas.
enum BatchRenamePresets {
    private static let key = "batchRenameUserPresets"

    /// Load user-created presets. Returns an empty array on first
    /// run / decode failure (which would only happen if a Settings
    /// migration shipped a malformed value — non-fatal, the user
    /// just sees an empty Manage list).
    static func loadUser() -> [FilenameRenamePreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([FilenameRenamePreset].self,
                                            from: data)) ?? []
    }

    static func saveUser(_ presets: [FilenameRenamePreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// System + user, in display order. Used by the Batch Rename
    /// pattern Picker.
    static func combined() -> [FilenameRenamePreset] {
        FilenameRenamePresetCatalog.system + loadUser()
    }

    /// Look up by id. Used when re-rendering after a Picker change
    /// and the only thing the view has is the sticky id.
    static func find(id: String) -> FilenameRenamePreset? {
        combined().first { $0.id == id }
    }

    /// Built-in variables surfaced by the "Add Variable" menu in
    /// `ManageFilenamePresetsSheet`. The keys are the names that
    /// land inside `${…}`; values are short display labels.
    static let variables: [(key: String, label: String)] = [
        ("customName",   "Custom Name"),
        ("originalName", "Original Name"),
        ("extension",    "Extension"),
        ("index",        "Index (1, 2, 3 …)"),
        ("globalIndex",  "Global Index (across batches)"),
        ("timecode",     "Source Timecode"),
        ("dateModified", "Date Modified"),
        ("markerTitle",  "First Marker Title"),
    ]
}
