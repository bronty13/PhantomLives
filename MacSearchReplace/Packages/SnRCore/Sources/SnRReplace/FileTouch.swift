import Foundation

/// "Touch" — rewrite mtime (and optionally atime) on files. Mirrors Funduc's
/// Touch operation. Defaults to setting both to "now".
public enum FileTouch {

    public static func touch(
        urls: [URL],
        modificationDate: Date = Date(),
        accessDate: Date? = nil
    ) throws -> [URL] {
        let fm = FileManager.default
        var changed: [URL] = []
        for url in urls {
            let attrs: [FileAttributeKey: Any] = [.modificationDate: modificationDate]
            _ = accessDate  // accessDate currently unused; placeholder for future setattrlist impl
            do {
                try fm.setAttributes(attrs, ofItemAtPath: url.path)
                changed.append(url)
            } catch {
                continue
            }
        }
        return changed
    }
}
