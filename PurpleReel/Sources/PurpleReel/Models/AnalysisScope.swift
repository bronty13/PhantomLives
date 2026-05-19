import Foundation

/// "Analysis Scope" dialog selections (Kyno-parity, Image #90).
/// Drives what `AppState.preAnalyzeSelected(scope:)` does — Kyno's
/// dialog lets the user pick which work to redo rather than always
/// re-running everything. Tech metadata + Thumbnails fully wired in
/// C13; Key frames stays in the model + dialog for shape parity but
/// is disabled-with-tooltip until a keyframe-extraction service
/// lands (separate from `ThumbnailService`'s evenly-distributed
/// strip).
struct AnalysisScope: OptionSet, Codable, Hashable {
    let rawValue: Int

    /// Re-runs `MediaScanner.loadAVTech(url:)` for each asset:
    /// duration, codec, dims, fps, audio codec, recordedAt, isVFR.
    /// This is what C7's Pre-analyze always did.
    static let technicalMetadata = AnalysisScope(rawValue: 1 << 0)

    /// Purge the asset's thumbnail-strip cache and force
    /// regeneration on next render. Useful when a source file's
    /// poster frame was wrong (e.g. embedded thumbnail differs from
    /// content) or when the user wants the strip rebuilt from a
    /// just-fixed source clip.
    static let thumbnails        = AnalysisScope(rawValue: 1 << 1)

    /// Reserved — scene-change keyframe extraction for hover-scrub
    /// at sub-second granularity. Different from the existing
    /// evenly-distributed strip. Off by default in Kyno; ships
    /// disabled in PurpleReel's dialog until extraction lands.
    static let keyFrames         = AnalysisScope(rawValue: 1 << 2)

    /// Kyno default per Image #90 — Technical metadata + Thumbnails
    /// on; Key frames off.
    static let `default`: AnalysisScope = [.technicalMetadata, .thumbnails]
}
