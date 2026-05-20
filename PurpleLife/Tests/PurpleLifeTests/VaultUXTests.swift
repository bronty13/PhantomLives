import XCTest
import LocalAuthentication
@testable import PurpleLife

/// Vault UX hardening (2026-05-20) — covers the small additions that
/// give the existing Vault auth flow user-facing controls:
///
/// - `AppSettings.biometryOnlyMode` lenient-decode + round-trip.
/// - `VaultAuthService.policy(biometryOnly:)` pure-function mapping.
/// - `LockScreenError` typed lock-screen error cases each carry
///   distinct user-facing copy + SF Symbols.
///
/// `LAContext` itself remains uncovered for the same reason
/// `VaultTests.swift` documents — biometry prompts require a real
/// device, not an XCTest stub.
final class VaultUXTests: XCTestCase {

    // MARK: - AppSettings.biometryOnlyMode

    /// Lock the lenient-decode contract for the new field: a
    /// `settings.json` written by a pre-2026-05-20 build has no
    /// `biometryOnlyMode` key. The custom `init(from:)` decoder uses
    /// `decodeIfPresent`, falling back to `false` — the safe default
    /// that preserves the historical behavior. Without this, every
    /// pre-existing install would have `init(from:)` throw on the
    /// first launch with the new build, `SettingsStore.load`'s
    /// `try?` would swallow the error, and the user would silently
    /// lose every previously-saved setting.
    func testBiometryOnlyModeDecodesAsFalseFromLegacySettings() throws {
        let legacyJSON = """
        {
            "autoBackupEnabled": true,
            "backupPath": "",
            "backupRetentionDays": 14,
            "lastBackupAt": "",
            "defaultExportDirectory": "",
            "todayQueries": [],
            "todayQueriesSeeded": true,
            "forecastDays": 30,
            "themeID": "royalPurple",
            "appearance": "system",
            "userThemes": [],
            "tagVocabulary": [],
            "vaultAutoLockAfterSeconds": 120
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertFalse(decoded.biometryOnlyMode,
                       "missing biometryOnlyMode key must decode as false, not throw")
        XCTAssertEqual(decoded.vaultAutoLockAfterSeconds, 120,
                       "neighboring fields must still decode correctly")
    }

    /// Setting biometryOnlyMode = true persists across an encode/
    /// decode cycle. Catches accidental synthesized-encoder drift if
    /// someone adds a custom `encode(to:)` and forgets the new key.
    func testBiometryOnlyModeRoundTripsViaCodable() throws {
        var s = AppSettings()
        s.biometryOnlyMode = true
        s.vaultAutoLockAfterSeconds = 300

        let encoded = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertTrue(decoded.biometryOnlyMode)
        XCTAssertEqual(decoded.vaultAutoLockAfterSeconds, 300)
    }

    // MARK: - VaultAuthService.policy

    /// Default (off): policy must be `.deviceOwnerAuthentication` so
    /// a Mac without Touch ID still opens the Vault via login
    /// password. Locking this here means a refactor that flips the
    /// default fails fast in tests.
    @MainActor
    func testPolicyDefaultsToDeviceOwnerAuthentication() {
        XCTAssertEqual(VaultAuthService.policy(biometryOnly: false),
                       LAPolicy.deviceOwnerAuthentication)
    }

    /// Biometry-only mode: policy switches to
    /// `.deviceOwnerAuthenticationWithBiometrics`, which refuses the
    /// password-entry fallback path. The pure-function shape is the
    /// testability seam — `LAContext.evaluatePolicy` itself stays
    /// untestable, but the policy choice doesn't need to be.
    @MainActor
    func testPolicySwitchesToBiometricsWhenBiometryOnly() {
        XCTAssertEqual(VaultAuthService.policy(biometryOnly: true),
                       LAPolicy.deviceOwnerAuthenticationWithBiometrics)
    }

    // MARK: - LockScreenError

    /// Each typed error case must carry a non-empty, distinct user-
    /// facing message — so the rendered lock screen tells the user
    /// what specifically went wrong (cancelled vs failed vs biometry
    /// unavailable vs biometry-only-mode-can't-evaluate). The detail
    /// strings inside `.failed`/`.unavailable`/`.biometryFailed`/
    /// `.biometryUnavailable` are interpolated, so we substitute a
    /// known sentinel and assert it surfaces.
    func testLockScreenErrorMessagesAreSpecificAndIncludeDetail() {
        let sentinel = "EVAL-DETAIL-XYZ"
        let cases: [(LockScreenError, String?)] = [
            (.cancelled, nil),
            (.failed(sentinel), sentinel),
            (.unavailable(sentinel), sentinel),
            (.biometryFailed(sentinel), sentinel),
            (.biometryUnavailable(sentinel), sentinel)
        ]
        var seen = Set<String>()
        for (err, mustContain) in cases {
            let msg = err.message
            XCTAssertFalse(msg.isEmpty, "\(err) message must be non-empty")
            XCTAssertTrue(seen.insert(msg).inserted,
                          "\(err) message must be distinct across cases (got duplicate: \(msg))")
            if let needle = mustContain {
                XCTAssertTrue(msg.contains(needle),
                              "\(err) message must surface the underlying detail string (got: \(msg))")
            }
        }
    }

    /// Symbols must distinguish biometry-specific failure modes from
    /// the generic ones so the user gets visual disambiguation
    /// without reading the caption. The biometry-only cases use
    /// distinct symbols from the password-fallback cases.
    func testLockScreenErrorSymbolsAreCaseDistinct() {
        // .biometryFailed shows the touchid symbol (specific cue —
        // "this is the fingerprint sensor failing"); .failed shows
        // the generic warning triangle.
        XCTAssertEqual(LockScreenError.biometryFailed("x").symbol, "touchid")
        XCTAssertEqual(LockScreenError.failed("x").symbol, "exclamationmark.triangle.fill")

        // .biometryUnavailable + .unavailable both mean "policy
        // can't even attempt" — they share the lock.slash symbol on
        // purpose. The message text disambiguates them.
        XCTAssertEqual(LockScreenError.biometryUnavailable("x").symbol, "lock.slash.fill")
        XCTAssertEqual(LockScreenError.unavailable("x").symbol, "lock.slash.fill")

        // .cancelled is the most benign state — back to the
        // base lock symbol, not an error treatment.
        XCTAssertEqual(LockScreenError.cancelled.symbol, "lock.fill")
    }
}
