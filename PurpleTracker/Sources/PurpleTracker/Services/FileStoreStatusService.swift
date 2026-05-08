import Foundation

/// Inspects a folder path: does it exist? how many files / how recently
/// modified? Lightweight stand-in for true OneDrive sync state (which
/// would require an OS-level File Provider extension).
enum FileStoreStatusService {

    struct Status {
        let exists: Bool
        let fileCount: Int
        let lastModified: Date?
    }

    static func status(forPath rawPath: String) -> Status {
        let expanded = (rawPath as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            return Status(exists: false, fileCount: 0, lastModified: nil)
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: expanded, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            return Status(exists: false, fileCount: 0, lastModified: nil)
        }
        guard let items = try? fm.contentsOfDirectory(atPath: expanded) else {
            return Status(exists: true, fileCount: 0, lastModified: nil)
        }
        var newest: Date? = nil
        var n = 0
        for name in items where !name.hasPrefix(".") {
            n += 1
            let full = (expanded as NSString).appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let mod = attrs[.modificationDate] as? Date {
                if newest == nil || mod > newest! { newest = mod }
            }
        }
        return Status(exists: true, fileCount: n, lastModified: newest)
    }
}
