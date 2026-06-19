import Foundation
import Testing
@testable import Ircle

@Suite("FaceGraphics")
struct FaceGraphicsTests {

    @Test func hueIsDeterministicAndCaseInsensitive() {
        // Same nick → same hue every call (not randomized like String.hashValue).
        #expect(FaceGraphics.hue(for: "alice") == FaceGraphics.hue(for: "alice"))
        // Folded: case doesn't change the color.
        #expect(FaceGraphics.hue(for: "Alice") == FaceGraphics.hue(for: "alice"))
        // Different nicks generally differ.
        #expect(FaceGraphics.hue(for: "alice") != FaceGraphics.hue(for: "bob"))
    }

    @Test func hueInUnitRange() {
        for nick in ["a", "longername", "x_y", "123", "ZZZ"] {
            let h = FaceGraphics.hue(for: nick)
            #expect(h >= 0 && h < 1)
        }
    }

    @Test func initialsFromTokens() {
        #expect(FaceGraphics.initials(for: "bob_smith") == "BS")
        #expect(FaceGraphics.initials(for: "alice") == "AL")
        #expect(FaceGraphics.initials(for: "x") == "X")
        #expect(FaceGraphics.initials(for: "!!!") == "?")
    }
}

@MainActor
@Suite("FacesStore")
struct FacesStoreTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-faces-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A throwaway file standing in for an image (FacesStore just copies bytes).
    private func sampleImage(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("src.png")
        try Data("not-really-a-png".utf8).write(to: url)
        return url
    }

    @Test func assignCopiesFileAndRecordsMapping() throws {
        let base = tempDir()
        let store = FacesStore(baseDir: base)
        let img = try sampleImage(in: base)

        #expect(store.hasImage(for: "Bob") == false)
        let filename = try store.assign(imageAt: img, to: "Bob")
        // Case-insensitive lookup.
        #expect(store.hasImage(for: "bob"))
        // File landed in the Faces/ subdir.
        let copied = base.appendingPathComponent("Faces").appendingPathComponent(filename)
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test func reassignReplacesPriorFile() throws {
        let base = tempDir()
        let store = FacesStore(baseDir: base)
        let img = try sampleImage(in: base)
        let first = try store.assign(imageAt: img, to: "bob")
        let second = try store.assign(imageAt: img, to: "bob")
        #expect(first != second)
        let facesDir = base.appendingPathComponent("Faces")
        #expect(!FileManager.default.fileExists(atPath: facesDir.appendingPathComponent(first).path))
        #expect(FileManager.default.fileExists(atPath: facesDir.appendingPathComponent(second).path))
    }

    @Test func clearRemovesAssignmentAndFile() throws {
        let base = tempDir()
        let store = FacesStore(baseDir: base)
        let img = try sampleImage(in: base)
        let filename = try store.assign(imageAt: img, to: "bob")
        store.clear("bob")
        #expect(store.hasImage(for: "bob") == false)
        let path = base.appendingPathComponent("Faces").appendingPathComponent(filename).path
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func assignmentsPersistAcrossInstances() throws {
        let base = tempDir()
        let img = try sampleImage(in: base)
        do {
            let store = FacesStore(baseDir: base)
            _ = try store.assign(imageAt: img, to: "carol")
        }
        // A fresh store over the same dir reloads the mapping from faces.json.
        let reloaded = FacesStore(baseDir: base)
        #expect(reloaded.hasImage(for: "carol"))
    }
}
