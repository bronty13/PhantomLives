import Foundation

/// Builds the exact `osxphotos export …` argument vector for a profile + pass. Kept pure
/// (no process execution) so the command line is unit-testable — the safest way to be sure
/// we never, e.g., drop `--update` and re-export 250 GB, or forget `--sidecar` and lose
/// metadata. `ExportEngine` runs whatever this produces.
public enum ExportPlan {

    /// Destination directory for a pass under the profile's primary archive root
    /// (primary base + archive subfolder, e.g. "/Volumes/Drive/Photos Archive/originals").
    public static func destination(profile: ArchiveProfile, pass: ExportPass) -> String {
        (profile.primaryArchiveRoot as NSString)
            .appendingPathComponent(profile.subdirectory(for: pass))
    }

    /// The full argv (excluding the osxphotos executable itself).
    ///
    /// Flag rationale:
    ///  - `--update`        incremental: only new/changed assets are copied each run.
    ///  - `--directory`     dated folder tree from the profile template.
    ///  - `--filename`      keep original filenames.
    ///  - `--sidecar XMP`   write per-file metadata sidecars (survives outside Photos)…
    ///  - `--exiftool`      …and also embed metadata into the file itself (belt + braces).
    ///  - `--touch-file`    set each file's mtime to the photo's date.
    ///  - `--retry 3`       ride out transient iCloud/download hiccups.
    ///  - `--edited-suffix` keep BOTH the original and any edited rendering.
    ///  - `--convert-to-jpeg` (jpeg pass only) emit a universally-openable JPEG set.
    ///  - `--download-missing` (opt-in) pull originals from iCloud on an Optimize-Storage host.
    ///  - `--use-photokit`  (with download-missing) fetch via PhotoKit, not the AppleScript
    ///                      path that times out and kills Photos on indeterminate iCloud assets.
    ///  - `--dry-run`       (opt-in) plan only; touch nothing.
    public static func arguments(
        profile: ArchiveProfile,
        pass: ExportPass,
        dryRun: Bool
    ) -> [String] {
        var args: [String] = ["export", destination(profile: profile, pass: pass)]

        if let lib = profile.photosLibraryPath, !lib.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--library", lib]
        }

        args += ["--update"]
        args += ["--directory", profile.directoryTemplate]
        args += ["--filename", "{original_name}"]
        args += ["--sidecar", "XMP"]
        args += ["--exiftool"]
        args += ["--touch-file"]
        args += ["--retry", "3"]
        args += ["--edited-suffix", "_edited"]

        if profile.downloadMissingFromICloud {
            args += ["--download-missing"]
            // PhotoKit is the reliable fetch path; the default AppleScript one times out and
            // kills Photos on slow/indeterminate iCloud assets. Only meaningful alongside
            // --download-missing.
            if profile.usePhotoKitForDownload {
                args += ["--use-photokit"]
            }
        }
        if pass == .jpeg {
            args += ["--convert-to-jpeg"]
        }
        if dryRun {
            args += ["--dry-run"]
        }

        return args
    }

    /// A copy-pasteable shell rendering of the command, for the plan view and the log.
    public static func shellCommand(
        osxphotos: String,
        profile: ArchiveProfile,
        pass: ExportPass,
        dryRun: Bool
    ) -> String {
        let parts = [osxphotos] + arguments(profile: profile, pass: pass, dryRun: dryRun)
        return parts.map { shellQuote($0) }.joined(separator: " ")
    }

    /// Minimal POSIX shell quoting so paths/templates with spaces render correctly.
    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./=:@%+")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
