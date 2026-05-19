import Foundation

/// "Report Definition" dialog selections (Kyno-parity, Image #89).
/// Toggles section groups in the CSV / HTML / XLSX reports so a
/// producer can slim a long report to "just the bits I need" before
/// it's written. File size + File type are always-on (locked in
/// Kyno's dialog) so every row carries the minimum identification
/// columns even when everything else is off.
struct ReportSections: OptionSet, Codable, Hashable {
    let rawValue: Int

    /// File size (bytes). Always on — locked in the dialog.
    static let fileSize           = ReportSections(rawValue: 1 << 0)
    /// File type (codec / container hint). Always on — locked.
    static let fileType           = ReportSections(rawValue: 1 << 1)
    /// Duration column. Default on, user can drop it.
    static let duration           = ReportSections(rawValue: 1 << 2)
    /// Format-detail bundle: resolution, display size, aspect ratio,
    /// FPS, audio codec. Default on; collapses the technical block.
    static let formatDetails      = ReportSections(rawValue: 1 << 3)
    /// Descriptive metadata bundle: title, description, reel/scene/
    /// shot/take/angle/camera, audio channel names, tags, rating.
    /// Default on; for stripped-down "Producer needs file list"
    /// reports the user drops it.
    static let descriptiveMetadata = ReportSections(rawValue: 1 << 4)

    /// Default = everything on. Kyno-shaped Image #89 starts with
    /// every checkbox ticked.
    static let all: ReportSections = [
        .fileSize, .fileType, .duration,
        .formatDetails, .descriptiveMetadata,
    ]

    /// The two locked sections — the dialog shows them disabled so
    /// the user understands they're always included. Decoupled into
    /// a static so the view can iterate without re-typing the set.
    static let locked: ReportSections = [.fileSize, .fileType]
}
