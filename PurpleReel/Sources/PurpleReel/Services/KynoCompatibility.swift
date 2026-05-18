import Foundation

/// One-click "I'm coming from Kyno" preset. Bulk-applies the four
/// behavior defaults where PurpleReel diverges from Kyno, so a
/// Kyno-trained user lands on familiar muscle memory without
/// digging through Settings:
///
/// 1. `playerJLMode` → `"jump5s"` (Kyno's J/L convention) instead of
///    PurpleReel's multi-rate shuttle (FCP/Premiere convention).
/// 2. `autoDrilldownCameraMedia` → `false`. Kyno added a toggle in
///    1.8.1 to NOT auto-walk DCIM / AVCHD / PRIVATE on mount;
///    PurpleReel's default is on, which surprises Kyno users.
/// 3. `useKynoTerminology` → `true`. View-mode label becomes
///    "Thumbnail" instead of "Grid" (Kyno's wording).
/// 4. `naturalFileSort` → `true`. `clip2` sorts before `clip10`
///    using `localizedStandardCompare`. Finder-default, matches
///    Kyno; PurpleReel's `localizedCaseInsensitiveCompare` puts
///    them in lexicographic order.
///
/// The keyboard shortcuts Kyno users expect (X mute, ⌘⇧D drilldown,
/// ⌘U subclip export, ⌃⌥E zebra, ⌃⌥W widescreen, Alt-Shift-O open
/// in default app, ⌘⌥M focus metadata) are wired UNCONDITIONALLY in
/// the menu bar — they're additive bindings, not mode-gated, so
/// PurpleReel-native users get them as bonus shortcuts.
enum KynoCompatibility {
    /// Master toggle key. UI reads/writes this; service uses it as
    /// the canonical "is the preset on" answer.
    static let modeKey = "kynoCompatibilityMode"
    /// One-shot flag — has the first-launch "Coming from Kyno?"
    /// sheet been presented yet? Once shown (regardless of answer)
    /// we don't ask again.
    static let promptShownKey = "kynoCompatibilityPromptShown"

    /// Individual default keys driven by the preset. Listed here so
    /// the apply/restore pair stays in lockstep and there's exactly
    /// one place to edit when a new default joins the preset.
    static let drivenKeys: [String] = [
        "playerJLMode",
        "autoDrilldownCameraMedia",
        "useKynoTerminology",
        "naturalFileSort",
    ]

    /// Kyno-friendly values for every driven key.
    private static let kynoDefaults: [String: Any] = [
        "playerJLMode": "jump5s",
        "autoDrilldownCameraMedia": false,
        "useKynoTerminology": true,
        "naturalFileSort": true,
    ]

    /// PurpleReel-native values for every driven key. Matches what
    /// each consumer's `@AppStorage` default would resolve to on a
    /// fresh install.
    private static let purpleReelDefaults: [String: Any] = [
        "playerJLMode": "shuttle",
        "autoDrilldownCameraMedia": true,
        "useKynoTerminology": false,
        "naturalFileSort": false,
    ]

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: modeKey)
    }

    /// Flip the master switch on and write every Kyno-default value.
    /// Existing AppStorage observers across the app pick up the
    /// changes via the per-key `UserDefaults.didChangeNotification`
    /// fan-out — no manual refresh required.
    static func apply() {
        for (key, value) in kynoDefaults {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.set(true, forKey: modeKey)
    }

    /// Flip the master switch off and restore every driven key to
    /// its PurpleReel-native value.
    static func restore() {
        for (key, value) in purpleReelDefaults {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.set(false, forKey: modeKey)
    }

    /// True if every driven key currently holds its Kyno-default
    /// value. Used by the Settings toggle to decide checked state —
    /// detects a user who edited a single key after applying the
    /// preset (e.g. flipped `playerJLMode` back to shuttle): the
    /// toggle goes off and the user is clearly in "mixed" territory.
    static func allDrivenKeysMatchKyno() -> Bool {
        for (key, expected) in kynoDefaults {
            let actual = UserDefaults.standard.object(forKey: key)
            if !valuesEqual(actual, expected) { return false }
        }
        return true
    }

    private static func valuesEqual(_ a: Any?, _ b: Any) -> Bool {
        if let ab = a as? Bool, let bb = b as? Bool { return ab == bb }
        if let astr = a as? String, let bstr = b as? String { return astr == bstr }
        return false
    }
}
