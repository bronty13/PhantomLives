// SnRCore — top-level façade re-exporting the engine submodules and providing
// the high-level Job orchestrator that the UI and CLI both call.

@_exported import SnRSearch
@_exported import SnRReplace
@_exported import SnRArchive
@_exported import SnRPDF
@_exported import SnREncoding
@_exported import SnRScript

import Foundation

public enum SnR {
    /// Library version. Bumped manually with each release.
    public static let version = "0.1.0-dev"
}
