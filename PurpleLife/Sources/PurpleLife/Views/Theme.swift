import SwiftUI

/// Static facade over the **currently active** `PurpleTheme`. Views read
/// `Theme.bg`, `Theme.accent`, etc. as plain Color properties; the actual
/// palette is swapped at runtime by `SettingsStore` writing to
/// `Theme.current` whenever `AppSettings.themeID` changes. AppState
/// republishes via Combine so observers re-render and pick up the new
/// colors on their next body evaluation.
///
/// Keeping the static-access shape (rather than `@Environment(\.theme)`)
/// means none of the dozens of subviews that use Theme need to add an
/// extra property wrapper — and child views inside structs without
/// AppState injection (Today timeline cards, etc.) still get the
/// active palette for free via the re-render cascade.
///
/// The default value is `.royalPurple` — see `PurpleTheme.royalPurple`
/// for the source-of-truth oklch palette from the design handoff.
enum Theme {

    /// The active palette. Mutated by `SettingsStore` whenever
    /// `settings.themeID` (or `settings.userThemes`) changes. Always
    /// touched on `@MainActor` — no synchronization needed.
    @MainActor static var current: PurpleTheme = .royalPurple

    // MARK: - Surfaces

    @MainActor static var bg: Color { current.bg.color }
    @MainActor static var sidebarOpaque: Color { current.sidebarOpaque.color }
    @MainActor static var card: Color { current.card.color }

    // MARK: - Text

    @MainActor static var text: Color { current.text.color }
    @MainActor static var textDim: Color { current.textDim.color }
    @MainActor static var textFaint: Color { current.textFaint.color }

    // MARK: - Lines

    @MainActor static var cardBorder: Color { current.cardBorder.color }
    @MainActor static var hairline: Color { current.hairline.color }
    @MainActor static var rowHover: Color { current.rowHover.color }

    // MARK: - Accent

    @MainActor static var accent: Color { current.accent.color }
    @MainActor static var accentSoft: Color { current.accentSoft.color }

    // MARK: - Derived

    /// Section header foreground — picks textFaint up so it reads at the
    /// small-caps sizes used in sidebar group titles.
    @MainActor static var sectionHeader: Color { current.textFaint.color }
}
