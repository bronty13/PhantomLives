import Foundation
import Testing
@testable import SlackSucker

/// Pure-function coverage for the four post-processors added after
/// the 1.0 baseline: HashService, OrientationBaker, MetadataStripper,
/// TranscriptionService. Each one's primary side effect is on disk —
/// these tests exercise the parts that don't need real binaries
/// (exiftool, ffmpeg, transcribe.py) and stub the rest by laying out
/// a temp run folder identical to what FileOrganizer produces.

private func tempRunFolder() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ss-pp-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for sub in ["Videos", "Photos", "Audio", "Other"] {
        try? FileManager.default.createDirectory(
            at: url.appendingPathComponent(sub, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    return url
}

private func write(_ bytes: [UInt8], to url: URL) {
    try? Data(bytes).write(to: url)
}

@Suite("HashService")
struct HashServiceTests {

    @Test("hashes are stable and match known sha256")
    func knownSha256() {
        let folder = tempRunFolder()
        // "hello\n" — sha256 = 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
        let payload: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x0a]
        write(payload, to: folder.appendingPathComponent("Other/hello.bin"))

        let result = HashService.run(runFolder: folder, algorithms: [.sha256])
        #expect(result.fileCount == 1)
        #expect(result.errors.isEmpty)
        let out = try? String(contentsOf: folder.appendingPathComponent("hashes.txt"))
        #expect(out?.contains("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03") == true)
        #expect(out?.contains("Other/hello.bin") == true)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("multiple algorithms produce separate sections")
    func multipleAlgos() {
        let folder = tempRunFolder()
        write([0x61], to: folder.appendingPathComponent("Photos/a.jpg"))
        let result = HashService.run(runFolder: folder, algorithms: [.md5, .sha1, .sha256])
        #expect(result.byAlgo[.md5] == 1)
        #expect(result.byAlgo[.sha1] == 1)
        #expect(result.byAlgo[.sha256] == 1)
        let body = try? String(contentsOf: folder.appendingPathComponent("hashes.txt"))
        #expect(body?.contains("# MD5") == true)
        #expect(body?.contains("# SHA-1") == true)
        #expect(body?.contains("# SHA-256") == true)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("no algorithms selected -> bails with error, no file written")
    func emptyAlgorithms() {
        let folder = tempRunFolder()
        let result = HashService.run(runFolder: folder, algorithms: [])
        #expect(result.fileCount == 0)
        #expect(!result.errors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("hashes.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("symlinks are skipped, hidden files are skipped")
    func skipsSymlinksAndHidden() {
        let folder = tempRunFolder()
        let target = folder.appendingPathComponent("Other/real.bin")
        write([0x00, 0x01], to: target)
        let symlink = folder.appendingPathComponent("Other/link.bin")
        try? FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let hidden = folder.appendingPathComponent("Other/.DS_Store")
        write([0xFF], to: hidden)
        let result = HashService.run(runFolder: folder, algorithms: [.sha256])
        // Only real.bin counts; .DS_Store skipped via skipsHiddenFiles,
        // link.bin skipped via isSymbolicLink check.
        #expect(result.fileCount == 1)
        try? FileManager.default.removeItem(at: folder)
    }
}

@Suite("MetadataStripper helpers")
struct MetadataStripperTests {

    @Test("no exiftool -> reports skip and writes log")
    func skipsWhenExiftoolMissing() {
        // We can't truly hide exiftool from a homebrew machine — but
        // we can verify that with no media in the folder, the service
        // returns 0 processed, 0 errors and writes a log either way.
        let folder = tempRunFolder()
        let result = MetadataStripper.run(runFolder: folder)
        #expect(result.filesProcessed == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("metadata-log.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("binary discovery checks common homebrew locations")
    func binaryDiscoveryShape() {
        // Documents the resolution order — if the user has exiftool on
        // their machine somewhere outside the standard locations, the
        // service won't find it and that's the documented contract.
        // This test just guards the resolution path against accidental
        // regressions in the lookup loop.
        let resolved = MetadataStripper.exiftoolBinary()
        if let resolved {
            #expect(FileManager.default.isExecutableFile(atPath: resolved))
        } // else: machine without exiftool installed; nothing to assert
    }
}

@Suite("OrientationBaker helpers")
struct OrientationBakerTests {

    @Test("empty run folder -> zero counts, log written")
    func empty() {
        let folder = tempRunFolder()
        let result = OrientationBaker.run(runFolder: folder)
        #expect(result.photosInspected == 0)
        #expect(result.videosInspected == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("orient-log.txt").path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("baking a non-image file is unsupported, never crashes")
    func nonImageUnsupported() {
        // Lay an empty .jpg down; CGImageSource fails to decode → the
        // outcome must be .error / .unsupported, never a fatal trap.
        let folder = tempRunFolder()
        let bogus = folder.appendingPathComponent("Photos/empty.jpg")
        write([], to: bogus)
        let outcome = OrientationBaker.bakePhoto(at: bogus)
        switch outcome {
        case .rotated, .alreadyUpright:
            Issue.record("empty file should never report rotated/upright")
        case .unsupported, .error:
            break  // expected
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("ffmpeg / ffprobe lookup returns nil or an executable path")
    func ffmpegLookup() {
        if let ff = OrientationBaker.ffmpegBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: ff))
        }
        if let probe = OrientationBaker.ffprobeBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: probe))
        }
    }
}

@Suite("TranscriptionService helpers")
struct TranscriptionServiceTests {

    @Test("binary resolver finds something or returns nil")
    func resolver() {
        if let (exe, leading) = TranscriptionService.resolveBinary() {
            #expect(FileManager.default.isExecutableFile(atPath: exe))
            // Sibling-checkout path implies a script in leading args.
            // PATH-shim hit implies leading is empty.
            #expect(leading.isEmpty || leading[0].hasSuffix(".py"))
        }
    }
}

@Suite("ArchiveOptions backwards compat")
struct ArchiveOptionsCompatTests {

    @Test("decodes pre-1.1 JSON without the post-processing fields")
    func legacyJSONDecode() throws {
        // Settings.json shape pre-1.1 — only the four original fields.
        let json = """
        {
          "includeFiles": true,
          "includeAvatars": false,
          "memberOnly": false,
          "organizeFiles": true
        }
        """.data(using: .utf8)!
        let opts = try JSONDecoder().decode(ArchiveOptions.self, from: json)
        // All new fields default to their safe-off / default-on values.
        #expect(opts.generateHashes == false)
        #expect(opts.hashAlgorithms == [.sha256])
        #expect(opts.transcribeMedia == false)
        #expect(opts.transcribeModel == .turbo)
        #expect(opts.stripPhotoMetadata == false)
        #expect(opts.bakeOrientation == false)
    }
}
