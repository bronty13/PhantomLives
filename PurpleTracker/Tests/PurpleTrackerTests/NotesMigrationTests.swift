import XCTest
import GRDB
@testable import PurpleTracker

@MainActor
final class NotesMigrationTests: XCTestCase {

    func testV8CreatesNoteTables() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try q.read { db in
            XCTAssertTrue(try db.tableExists("note_type"))
            XCTAssertTrue(try db.tableExists("generic_note"))
        }
    }

    func testV8SeedsDefaultNoteTypes() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        let names: [String] = try q.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM note_type ORDER BY sort_order")
        }
        for expected in ["Staff", "Architecture", "Team", "SCRUM", "Third Party"] {
            XCTAssertTrue(names.contains(expected), "missing default note type: \(expected)")
        }
    }

    func testRTFRoundtrip() throws {
        let s = NSMutableAttributedString(string: "Hello, world.")
        s.addAttribute(.font,
                       value: NSFont.boldSystemFont(ofSize: 14),
                       range: NSRange(location: 0, length: 5))
        let data = s.toRTFData()
        XCTAssertNotNil(data)
        let restored = NSAttributedString.fromRTFData(data)
        XCTAssertEqual(restored.string, "Hello, world.")
    }

    func testRTFDRoundtripPreservesImageAttachment() throws {
        // Build a tiny PNG and wrap it in an NSTextAttachment exactly the
        // way NSTextView does when a user pastes an image.
        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not synthesize PNG bytes")
        }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "img.png"
        let att = NSTextAttachment(fileWrapper: wrapper)

        let composed = NSMutableAttributedString(string: "before ")
        composed.append(NSAttributedString(attachment: att))
        composed.append(NSAttributedString(string: " after"))

        let data = composed.toRTFData()
        XCTAssertNotNil(data, "RTFD encoding should not fail")
        let restored = NSAttributedString.fromRTFData(data)
        XCTAssertTrue(restored.string.contains("before"))
        XCTAssertTrue(restored.string.contains("after"))
        var sawAttachment = false
        restored.enumerateAttribute(.attachment,
                                    in: NSRange(location: 0, length: restored.length),
                                    options: []) { v, _, _ in
            if v is NSTextAttachment { sawAttachment = true }
        }
        XCTAssertTrue(sawAttachment, "Image attachment must survive RTFD round-trip")
    }

    func testRTFDRoundtripPreservesImageWhenAttachmentHasOnlyImage() throws {
        // Simulate NSTextView's paste path: attachment carries `image`. On
        // modern macOS this auto-creates a fileWrapper; on older or unusual
        // paths it may not. Either way the round-trip must preserve bytes.
        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let att = NSTextAttachment()
        att.image = img

        let composed = NSMutableAttributedString(string: "x")
        composed.append(NSAttributedString(attachment: att))

        let data = composed.toRTFData()
        XCTAssertNotNil(data)
        let restored = NSAttributedString.fromRTFData(data)
        var sawAttachmentWithBytes = false
        restored.enumerateAttribute(.attachment,
                                    in: NSRange(location: 0, length: restored.length),
                                    options: []) { v, _, _ in
            if let a = v as? NSTextAttachment,
               let fw = a.fileWrapper,
               let bytes = fw.regularFileContents,
               !bytes.isEmpty {
                sawAttachmentWithBytes = true
            }
        }
        XCTAssertTrue(sawAttachmentWithBytes,
                      "Image-only attachment must round-trip with bytes intact")
    }
}
