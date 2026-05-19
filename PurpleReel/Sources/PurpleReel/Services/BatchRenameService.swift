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

    /// `${variable}` syntax used by Kyno-shaped preset templates.
    /// Normalized to the engine's existing `{variable}` form on the
    /// way in so a single token-expander handles both. Both syntaxes
    /// can coexist in a single template (existing PurpleReel `{date}`
    /// patterns keep working alongside new `${customName}` ones).
    static func normalize(template: String) -> String {
        var out = template
        // Replace `${…}` → `{…}` for the recognized Kyno variables
        // listed in `BatchRenamePresets.variables`. Unknown `${…}`
        // tokens pass through unchanged so a typo is visible in the
        // preview (mirrors the legacy unknown-`{token}` behavior).
        for (key, _) in BatchRenamePresets.variables {
            // Each variable maps onto an engine-side token. Some
            // alias to existing PurpleReel tokens (originalName →
            // orig, extension → ext, dateModified → date,
            // index → counter).
            let target = engineToken(for: key)
            out = out.replacingOccurrences(of: "${\(key)}",
                                            with: "{\(target)}")
        }
        return out
    }

    /// Map a Kyno-style `${variable}` name onto the existing engine
    /// `{token}` name. Variables introduced in C10 (customName /
    /// timecode / markerTitle / globalIndex) keep their key as-is
    /// and have their own token handlers in `value(forToken:…)`.
    private static func engineToken(for variable: String) -> String {
        switch variable {
        case "originalName": return "orig"
        case "extension":    return "ext"
        case "dateModified": return "date"
        case "index":        return "counter"
        default:             return variable   // customName / timecode / etc.
        }
    }

    /// Build a plan over the given assets without touching disk.
    static func plan(template: String,
                     items: [Asset],
                     startCounter: Int = 1,
                     customName: String = "") -> [BatchRenamePlan] {
        var plans: [BatchRenamePlan] = []
        plans.reserveCapacity(items.count)
        var seenNames: Set<String> = []
        let fm = FileManager.default

        // Normalize `${variable}` syntax first so the per-row expander
        // only sees one form. Hot path is single-template-many-assets,
        // so doing this once outside the loop is the right shape.
        let normalized = normalize(template: template)

        for (idx, asset) in items.enumerated() {
            let originalURL = URL(fileURLWithPath: asset.path)
            let modified = asset.modifiedAt
            let name = expand(template: normalized, asset: asset,
                              originalURL: originalURL, modified: modified,
                              counter: startCounter + idx,
                              customName: customName)
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

    /// Expand a template against a URL alone — used by the
    /// "Paste & rename" flow where the source files aren't
    /// catalogued yet. Resolves `{orig}` / `{ext}` / `{date}` /
    /// `{counter}` from the URL + its filesystem mtime; leaves
    /// catalog-only tokens (`{codec}`, `{fps}`, etc.) as literal
    /// `{token}` placeholders so the user sees them in the preview.
    static func expandForPaste(template: String,
                                url: URL,
                                counter: Int) -> String {
        let mtime = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate]
            as? Date) ?? Date()
        return expandTokens(template: template, urlOnlyURL: url,
                             modified: mtime, counter: counter)
    }

    /// Expansion helper that works without an Asset — only resolves
    /// URL-derived tokens. Used by both the regular rename (which
    /// passes nil for the asset when it wants the cheap path) and
    /// the paste-with-rename flow.
    private static func expandTokens(template: String,
                                       urlOnlyURL: URL,
                                       modified: Date,
                                       counter: Int) -> String {
        var out = ""
        var i = template.startIndex
        let end = template.endIndex
        while i < end {
            let c = template[i]
            if c == "{", let close = template[i...].firstIndex(of: "}") {
                let body = String(template[template.index(after: i)..<close])
                let resolved = urlOnlyValue(
                    forToken: body, url: urlOnlyURL,
                    modified: modified, counter: counter
                )
                out += resolved ?? "{\(body)}"
                i = template.index(after: close)
            } else {
                out.append(c)
                i = template.index(after: i)
            }
        }
        return out
    }

    /// URL-only token resolver. Returns nil for catalog-derived
    /// tokens (codec / fps / w / h / size_mb) so `expandTokens`
    /// leaves them as literals — the user sees the typo or the
    /// "no metadata yet" reality in the preview.
    private static func urlOnlyValue(forToken token: String,
                                       url: URL,
                                       modified: Date,
                                       counter: Int) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1)
        let key = String(parts[0]).lowercased()
        let spec = parts.count > 1 ? String(parts[1]) : nil
        switch key {
        case "orig":
            return url.deletingPathExtension().lastPathComponent
        case "ext":
            let e = url.pathExtension
            return e.isEmpty ? "" : "." + e
        case "date":
            let fmt = DateFormatter()
            fmt.dateFormat = spec ?? "yyyy-MM-dd"
            return fmt.string(from: modified)
        case "counter":
            if let s = spec, let pad = Int(s) {
                return String(format: "%0\(pad)d", counter)
            }
            return String(counter)
        default:
            return nil   // catalog-derived; leave literal
        }
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
                                counter: Int,
                                customName: String = "") -> String {
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
                             counter: counter,
                             customName: customName) ?? "{\(tokenBody)}"
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
                               counter: Int,
                               customName: String = "") -> String? {
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
        // Kyno-shaped variables (C10). Most alias to existing tokens
        // via `normalize(template:)`; these are the C10-only ones.
        case "customname":
            return customName
        case "timecode":
            // Use embedded source timecode if available, else fall
            // back to the file's modified-time as a TC-shaped stamp.
            // Format: HHMMSS — filename-safe (no colons).
            let date = asset.recordedAt ?? modified
            let f = DateFormatter()
            f.dateFormat = "HHmmss"
            return f.string(from: date)
        case "globalindex":
            // Monotonic counter across batches. Stored in
            // UserDefaults so the next batch picks up where the
            // previous one stopped.
            let bumped = UserDefaults.standard
                .integer(forKey: "batchRenameGlobalIndex") + 1
            UserDefaults.standard.set(bumped,
                                        forKey: "batchRenameGlobalIndex")
            let width = spec.flatMap { Int($0) } ?? 4
            return width > 0
                ? String(format: "%0\(width)d", bumped)
                : String(bumped)
        case "markertitle":
            // First marker on the asset (if catalogued). The service
            // doesn't have DB access; the view layer can pre-populate
            // this by overriding the token before the batch runs.
            // For now, leaves a literal placeholder so the user sees
            // the gap in the preview.
            return ""
        default:
            return nil  // unknown token: caller leaves it literal
        }
    }
}
