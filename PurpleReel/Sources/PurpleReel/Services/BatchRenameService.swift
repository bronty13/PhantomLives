import Foundation

/// One row in a rename preview / plan.
struct BatchRenamePlan: Identifiable, Equatable {
    let id = UUID()
    let originalURL: URL
    let proposedName: String
    let proposedURL: URL
    let conflicts: Bool   // destination already exists (and isn't the source)

    var isNoop: Bool {
        originalURL.lastPathComponent == proposedName
    }
}

/// Token-based renamer. Supported tokens:
///   `{orig}`     — original basename without extension
///   `{ext}`      — original extension, with leading dot
///   `{date}`     — file's last-modified date, `YYYY-MM-DD`
///   `{date:fmt}` — custom DateFormatter spec, e.g. `{date:yyyyMMdd}`
///   `{counter}`  — 1-based sequence number across the batch
///   `{counter:N}` — counter zero-padded to N digits, e.g. `{counter:04}`
///   `{codec}`    — codec from the catalog (lowercased)
///   `{fps}`      — frame rate, formatted with 2 decimals (29.97)
///   `{w}` / `{h}` — pixel width / height
///   `{size_mb}`  — file size in MB, integer
///
/// Any unrecognized `{token}` is left literal so the user can spot
/// typos in the preview.
enum BatchRenameService {

    /// Build a plan over the given assets without touching disk.
    static func plan(template: String,
                     items: [Asset],
                     startCounter: Int = 1) -> [BatchRenamePlan] {
        var plans: [BatchRenamePlan] = []
        plans.reserveCapacity(items.count)
        var seenNames: Set<String> = []
        let fm = FileManager.default

        for (idx, asset) in items.enumerated() {
            let originalURL = URL(fileURLWithPath: asset.path)
            let modified = asset.modifiedAt
            let name = expand(template: template, asset: asset,
                              originalURL: originalURL, modified: modified,
                              counter: startCounter + idx)
            let dir = originalURL.deletingLastPathComponent()
            let proposedURL = dir.appendingPathComponent(name)
            let lowerName = name.lowercased()

            // Conflict: name collides with another in this batch, OR
            // already exists on disk and isn't the same file.
            var conflict = seenNames.contains(lowerName)
            if !conflict, fm.fileExists(atPath: proposedURL.path),
               proposedURL.path != originalURL.path {
                conflict = true
            }
            seenNames.insert(lowerName)

            plans.append(BatchRenamePlan(
                originalURL: originalURL,
                proposedName: name,
                proposedURL: proposedURL,
                conflicts: conflict
            ))
        }
        return plans
    }

    /// Apply a plan: rename each file on disk and return a list of
    /// (oldPath → newPath) tuples for DB updates. Skips no-ops and
    /// conflicts. Stops at the first hard error.
    static func apply(_ plans: [BatchRenamePlan]) throws -> [(old: String, new: String)] {
        var moved: [(old: String, new: String)] = []
        for plan in plans {
            if plan.isNoop || plan.conflicts { continue }
            try FileManager.default.moveItem(at: plan.originalURL, to: plan.proposedURL)
            moved.append((plan.originalURL.path, plan.proposedURL.path))
        }
        return moved
    }

    // MARK: - Token expansion

    private static func expand(template: String, asset: Asset,
                                originalURL: URL, modified: Date,
                                counter: Int) -> String {
        var out = ""
        var i = template.startIndex
        let end = template.endIndex
        while i < end {
            let c = template[i]
            if c == "{",
               let close = template[i...].firstIndex(of: "}") {
                let tokenBody = String(template[template.index(after: i)..<close])
                out += value(forToken: tokenBody, asset: asset,
                             originalURL: originalURL, modified: modified,
                             counter: counter) ?? "{\(tokenBody)}"
                i = template.index(after: close)
            } else {
                out.append(c)
                i = template.index(after: i)
            }
        }
        // Normalize: strip slashes (would create directories), trim spaces.
        out = out.replacingOccurrences(of: "/", with: "_")
        out = out.trimmingCharacters(in: .whitespaces)
        // Always ensure we have an extension — default to the original.
        if (out as NSString).pathExtension.isEmpty {
            out += originalURL.pathExtension.isEmpty ? "" : ".\(originalURL.pathExtension)"
        }
        return out
    }

    private static func value(forToken token: String, asset: Asset,
                               originalURL: URL, modified: Date,
                               counter: Int) -> String? {
        // Split on first ":" for tokens with a format spec.
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts[0].lowercased()
        let spec: String? = parts.count > 1 ? parts[1] : nil

        switch key {
        case "orig":
            return originalURL.deletingPathExtension().lastPathComponent
        case "ext":
            let ext = originalURL.pathExtension
            return ext.isEmpty ? "" : ".\(ext)"
        case "date":
            let f = DateFormatter()
            f.dateFormat = spec ?? "yyyy-MM-dd"
            return f.string(from: modified)
        case "counter":
            let width = spec.flatMap { Int($0) } ?? 0
            return width > 0
                ? String(format: "%0\(width)d", counter)
                : String(counter)
        case "codec":
            return (asset.codec ?? "").lowercased()
        case "fps":
            guard let fps = asset.frameRate else { return "" }
            return String(format: "%.2f", fps)
        case "w":
            return asset.widthPx.map { String($0) } ?? ""
        case "h":
            return asset.heightPx.map { String($0) } ?? ""
        case "size_mb":
            return String(asset.sizeBytes / (1024 * 1024))
        default:
            return nil  // unknown token: caller leaves it literal
        }
    }
}
