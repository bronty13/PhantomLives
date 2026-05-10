import Foundation

/// Identifiable wrapper for the per-Photos-library filter sheet's URL.
/// Lives at the top level (not nested in ContentView) so SwiftUI's diffing
/// has a stable type identity across body evaluations and so the
/// extracted `SourcesStrip` view can refer to it directly.
///
/// Drives `.sheet(item:)` — the single non-nil-or-nil state transition is
/// atomic, which avoided a nasty race where a paired `URL? + Bool` setup
/// rendered an empty white sheet because SwiftUI evaluated the URL
/// optional before the Bool flip committed.
struct PhotoFilterSheetItem: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
}
