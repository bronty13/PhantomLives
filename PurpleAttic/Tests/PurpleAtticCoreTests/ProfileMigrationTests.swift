import XCTest
@testable import PurpleAtticCore

/// The profile JSON is shared by the CLI, the GUI, and the scheduler and outlives any single
/// release, so decoding must tolerate older files. These guard the `archiveSubfolder`
/// addition (0.6) specifically: a pre-0.6 profile that predates the key must still load,
/// defaulting to "Photos Archive" rather than throwing.
final class ProfileMigrationTests: XCTestCase {

    private func decode(_ json: String) throws -> ArchiveProfile {
        try JSONDecoder().decode(ArchiveProfile.self, from: Data(json.utf8))
    }

    func testPre06ProfileWithoutSubfolderDefaults() throws {
        // A realistic older profile: every old key present, no archiveSubfolder.
        let json = """
        {
          "id": "C69A2546-5B8D-40E9-8DAC-EC0D167B110F",
          "name": "Main Photo Archive",
          "primaryDestination": "/Volumes/PRO-G40",
          "mirrorDestinations": ["/Volumes/Mirror"],
          "keepHEIC": true,
          "keepJPEG": true,
          "directoryTemplate": "{created.year}/{created.year}-{created.mm}",
          "downloadMissingFromICloud": false,
          "retention": {"keepWindowDays": 365, "keepAlbumNames": ["Save"], "keepKeywords": ["save"], "keepFavorites": false},
          "purgeEnabled": false
        }
        """
        let p = try decode(json)
        XCTAssertEqual(p.archiveSubfolder, "Photos Archive", "missing key must default, not throw")
        XCTAssertEqual(p.primaryDestination, "/Volumes/PRO-G40")
        XCTAssertEqual(p.primaryArchiveRoot, "/Volumes/PRO-G40/Photos Archive")
        XCTAssertEqual(p.name, "Main Photo Archive")
        XCTAssertFalse(p.purgeEnabled)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let p = try decode("{}")
        XCTAssertEqual(p.archiveSubfolder, "Photos Archive")
        XCTAssertEqual(p.name, "Main Photo Archive")
        XCTAssertTrue(p.keepHEIC)
        XCTAssertTrue(p.keepJPEG)
        XCTAssertFalse(p.downloadMissingFromICloud)
    }

    func testExplicitSubfolderPreserved() throws {
        let p = try decode(#"{"primaryDestination":"/Volumes/X","archiveSubfolder":"Backups/Photos"}"#)
        XCTAssertEqual(p.archiveSubfolder, "Backups/Photos")
        XCTAssertEqual(p.primaryArchiveRoot, "/Volumes/X/Backups/Photos")
    }

    func testRoundTripPreservesSubfolder() throws {
        var p = ArchiveProfile(name: "RT", primaryDestination: "/Volumes/X")
        p.archiveSubfolder = "Photos Archive"
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ArchiveProfile.self, from: data)
        XCTAssertEqual(back.archiveSubfolder, "Photos Archive")
        XCTAssertEqual(back, p)
    }
}
