import Foundation
import AppKit

/// Looks up user-supplied scans (suspect cards, manual pages, box art, audio
/// cues) at runtime so they can be dropped in without rebuilding.
///
/// Canonical location: `~/Documents/ElectronicDetective Assets/`. That tree
/// is created on first launch with a README explaining the file-naming
/// convention. Anything missing falls back to a generated placeholder — the
/// app stays playable bare.
@MainActor
final class AssetResolver: ObservableObject {
    static let shared = AssetResolver()

    /// Bumped whenever the resolver invalidates its caches so SwiftUI views
    /// that observe it re-render. M2 invalidates manually via `refresh()`;
    /// a real file-system watcher is an M5 improvement.
    @Published private(set) var revision: Int = 0

    let assetsRoot: URL
    let suspectsDir: URL
    let manualDir: URL
    let boxDir: URL
    let audioDir: URL
    let notepadDir: URL

    private var imageCache: [URL: NSImage] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        assetsRoot  = docs.appendingPathComponent("ElectronicDetective Assets", isDirectory: true)
        suspectsDir = assetsRoot.appendingPathComponent("suspects",  isDirectory: true)
        manualDir   = assetsRoot.appendingPathComponent("manual",    isDirectory: true)
        boxDir      = assetsRoot.appendingPathComponent("box",       isDirectory: true)
        audioDir    = assetsRoot.appendingPathComponent("audio",     isDirectory: true)
        notepadDir  = assetsRoot.appendingPathComponent("notepad",   isDirectory: true)
        createIfNeeded()
    }

    /// Creates the asset tree and writes a README on first launch. Idempotent.
    func createIfNeeded() {
        let fm = FileManager.default
        for dir in [assetsRoot, suspectsDir, manualDir, boxDir, audioDir, notepadDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let readme = assetsRoot.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let body = """
            Electronic Detective — user assets

            Drop your own scans / recordings here. Anything missing is
            replaced by a generated placeholder; the app stays playable bare.

            suspects/   suspect_01.png … suspect_20.png  (any aspect ratio)
            manual/     page_01.png … page_NN.png  (or .pdf)
            box/        front.png, back.png
            audio/      bong.wav, gunshot.wav, siren.wav, dirge.wav, key.wav
            notepad/    sheet.png  (optional pad background overlay)
            """
            try? body.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    /// Force a cache flush. Views that need to pick up newly-dropped files
    /// (e.g. the Settings panel's "Refresh assets" button) call this.
    func refresh() {
        imageCache.removeAll(keepingCapacity: true)
        revision &+= 1
    }

    // MARK: - Suspect cards

    func suspectImage(id: Int) -> NSImage? {
        let candidates = ["png", "jpg", "jpeg", "heic", "tiff"].map {
            suspectsDir.appendingPathComponent("suspect_\(String(format: "%02d", id)).\($0)")
        }
        return firstImage(in: candidates)
    }

    // MARK: - Manual pages

    /// All manual pages in lexicographic order (so `page_01.png` precedes
    /// `page_02.png`). Returns both images and PDFs — the booklet viewer
    /// handles either.
    func manualPageURLs() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: manualDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let supported: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]
        return entries
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Box art

    func boxFront() -> NSImage? { firstImage(filenameStem: "front", in: boxDir) }
    func boxBack()  -> NSImage? { firstImage(filenameStem: "back",  in: boxDir) }

    // MARK: - Audio

    enum AudioCue: String, CaseIterable {
        case bong, gunshot, siren, dirge, key
    }

    /// URL for the user's recording of a cue, if present. `nil` means
    /// `SoundBank` should synthesize the cue.
    func audioURL(_ cue: AudioCue) -> URL? {
        let exts = ["wav", "caf", "aiff", "mp3", "m4a"]
        for ext in exts {
            let u = audioDir.appendingPathComponent("\(cue.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Notepad overlay

    func notepadOverlay() -> NSImage? { firstImage(filenameStem: "sheet", in: notepadDir) }

    // MARK: - Helpers

    private func firstImage(in urls: [URL]) -> NSImage? {
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) {
                if let cached = imageCache[url] { return cached }
                if let img = NSImage(contentsOf: url) {
                    imageCache[url] = img
                    return img
                }
            }
        }
        return nil
    }

    private func firstImage(filenameStem stem: String, in dir: URL) -> NSImage? {
        let candidates = ["png", "jpg", "jpeg", "heic", "tiff"].map {
            dir.appendingPathComponent("\(stem).\($0)")
        }
        return firstImage(in: candidates)
    }
}
