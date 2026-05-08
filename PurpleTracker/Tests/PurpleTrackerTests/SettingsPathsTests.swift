import XCTest
@testable import PurpleTracker

@MainActor
final class SettingsPathsTests: XCTestCase {

    /// Default backup path lives under the per-app `~/Downloads/PurpleTracker/`
    /// umbrella as `Backup/`, never as a sibling `PurpleTracker backup` folder.
    func testDefaultBackupPathIsUnderUmbrellaFolder() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-settings-\(UUID().uuidString).json")
        let store = SettingsStore(fileURL: tmp)
        let p = store.resolvedBackupPath.path
        XCTAssertTrue(p.hasSuffix("/Downloads/PurpleTracker/Backup"),
                      "Default backup path should end with Downloads/PurpleTracker/Backup, got \(p)")
        XCTAssertFalse(p.contains("PurpleTracker backup"),
                       "Default backup path must not use the legacy 'PurpleTracker backup' folder")
    }

    /// Default export path also nests under the umbrella as `Exports/`.
    func testDefaultExportPathIsUnderUmbrellaFolder() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-settings-\(UUID().uuidString).json")
        let store = SettingsStore(fileURL: tmp)
        let p = store.resolvedExportDirectory.path
        XCTAssertTrue(p.hasSuffix("/Downloads/PurpleTracker/Exports"),
                      "Default export path should end with Downloads/PurpleTracker/Exports, got \(p)")
    }

    /// Default secondary file-store template nests new Matter folders under
    /// `Files/` so they don't sit alongside `Backup/` and `Exports/`.
    func testDefaultSecondaryFileStoreTemplateIsUnderFilesSubfolder() throws {
        let s = AppSettings()
        XCTAssertEqual(s.fileStoreSecondaryTemplate, "~/Downloads/PurpleTracker/Files/{title}")
    }
}
