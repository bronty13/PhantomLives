import Foundation

/// Audio can't enter the Photos library, so a kept audio file is copied into the
/// configurable "Kept Audio Export" folder instead. Filenames are preserved; collisions get
/// a numeric suffix. The original on disk is left untouched.
enum AudioKeepService {

    enum ExportError: Error, LocalizedError {
        case sourceMissing
        case copyFailed(String)
        var errorDescription: String? {
            switch self {
            case .sourceMissing:        return "The audio file no longer exists on disk."
            case .copyFailed(let s):    return "Couldn't copy the audio file: \(s)"
            }
        }
    }

    /// Copy `source` into `destinationDir` (created on demand), de-duplicating the name.
    /// Returns the written URL.
    @discardableResult
    static func export(source: URL, to destinationDir: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw ExportError.sourceMissing }
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let dest = uniqueDestination(for: source.lastPathComponent, in: destinationDir, fm: fm)
        do {
            try fm.copyItem(at: source, to: dest)
        } catch {
            throw ExportError.copyFailed(error.localizedDescription)
        }
        return dest
    }

    /// Append " 2", " 3", … before the extension until the name is free.
    static func uniqueDestination(for fileName: String, in dir: URL, fm: FileManager = .default) -> URL {
        let candidate = dir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }
}
