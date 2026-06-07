import FinderSync
import ArchiveKit
import AppKit

/// Finder right-click integration: "Extract Here" for archives and "Compress
/// to…" for any selection, powered by the shared ArchiveKit engine. Work runs
/// on a background queue; results land next to the source in Finder.
final class ArchiveFinderSync: FIFinderSync {

    /// Extensions we'll offer "Extract Here" for (engine covers more, but the
    /// menu only needs a cheap recognizer).
    private static let archiveExts: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz",
        "zst", "tzst", "cab", "iso", "lha", "lzh", "cpio", "ar", "xar",
        "sit", "sitx", "cpt", "hqx", "bin",
    ]

    override init() {
        super.init()
        // Finder Sync only offers menus under directories we "monitor". Watch the
        // home folder and mounted volumes so the menu is broadly available.
        var dirs: Set<URL> = [FileManager.default.homeDirectoryForCurrentUser]
        dirs.insert(URL(fileURLWithPath: "/Volumes"))
        FIFinderSyncController.default().directoryURLs = dirs
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return nil }

        let root = NSMenu()
        let parent = NSMenuItem(title: "Purple Archive", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        if urls.contains(where: { Self.archiveExts.contains($0.pathExtension.lowercased()) }) {
            sub.addItem(withTitle: "Extract Here", action: #selector(extractHere(_:)), keyEquivalent: "")
        }
        sub.addItem(withTitle: "Compress to ZIP", action: #selector(compressZip(_:)), keyEquivalent: "")
        sub.addItem(withTitle: "Compress to TAR.ZST", action: #selector(compressZst(_:)), keyEquivalent: "")
        sub.addItem(withTitle: "Compress to 7z", action: #selector(compress7z(_:)), keyEquivalent: "")

        parent.submenu = sub
        root.addItem(parent)
        return root
    }

    // MARK: - Actions

    @objc private func extractHere(_ sender: AnyObject?) {
        let urls = (FIFinderSyncController.default().selectedItemURLs() ?? [])
            .filter { Self.archiveExts.contains($0.pathExtension.lowercased()) }
        run {
            let svc = ArchiveService()
            for url in urls {
                let dest = url.deletingPathExtension()  // <name>/ beside the archive
                try? svc.extract(url, options: ExtractOptions(destination: dest))
            }
        }
    }

    @objc private func compressZip(_ sender: AnyObject?) { compress(format: .zip, ext: "zip") }
    @objc private func compressZst(_ sender: AnyObject?) { compress(format: .tarZst, ext: "tar.zst") }
    @objc private func compress7z(_ sender: AnyObject?) { compress(format: .sevenZip, ext: "7z") }

    private func compress(format: ArchiveFormat, ext: String) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let out = Self.uniqueURL(dir.appendingPathComponent("\(base).\(ext)"))
        run {
            try? ArchiveService().create(out, inputs: urls, format: format)
        }
    }

    // MARK: - Helpers

    /// Run heavy work off the menu thread so Finder stays responsive.
    private func run(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            work()
            NSSound(named: "Glass")?.play()
        }
    }

    /// Avoid clobbering an existing file: foo.zip → foo 2.zip → …
    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(name) \(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
