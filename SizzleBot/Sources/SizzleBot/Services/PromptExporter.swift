import Foundation
import AppKit

/// Parses Likeness Architect output (or any response with a "Style variants:"
/// line) into a paragraph + list of variant tags, and forwards the resulting
/// prompts to a local Stable-Diffusion app via clipboard + launch.
///
/// Neither Draw Things nor DiffusionBee documents a URL scheme for prompt
/// prefill, so the supported flow is: copy prompt → bring the app to front →
/// the user pastes with ⌘V. We surface that explicitly in the UI.
enum PromptExporter {

    // MARK: Parsing

    struct Parsed: Equatable {
        let paragraph: String
        let variants: [String]
    }

    /// Splits an assistant response into the descriptive paragraph and any
    /// style-variant tags following a "Style variants:" line. Tolerant of
    /// case, whitespace, and punctuation around the prefix and the comma
    /// separators between tags.
    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(paragraph: "", variants: []) }

        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmpty = lines.enumerated().filter {
            !$0.element.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !nonEmpty.isEmpty else { return Parsed(paragraph: trimmed, variants: []) }

        // The variant line is the LAST line whose trimmed lowercase starts
        // with "style variants". Anchoring on `last` so a paragraph that
        // happens to mention "style variants" mid-text isn't misread.
        guard let variantPair = nonEmpty.reversed().first(where: {
            $0.element.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .hasPrefix("style variants")
        }) else {
            return Parsed(paragraph: trimmed, variants: [])
        }

        let variantLine = variantPair.element
        let variantIndex = variantPair.offset

        guard let prefixRange = variantLine.range(of: "style variants",
                                                  options: .caseInsensitive) else {
            return Parsed(paragraph: trimmed, variants: [])
        }

        let after = String(variantLine[prefixRange.upperBound...])
        let stripped = after.trimmingCharacters(in: CharacterSet(charactersIn: ":-—–·• \t"))
        let variants = stripped
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Paragraph = original lines minus the variant line, re-joined.
        let paragraph = lines.enumerated()
            .filter { $0.offset != variantIndex }
            .map { $0.element }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Parsed(paragraph: paragraph, variants: variants)
    }

    /// Joins a paragraph and a single style variant into one prompt string.
    /// Returns the paragraph unchanged when no variant is supplied.
    static func composePrompt(paragraph: String, variant: String?) -> String {
        let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = variant?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            return trimmedParagraph
        }
        if trimmedParagraph.isEmpty { return v }
        return "\(trimmedParagraph), \(v)"
    }

    // MARK: Targets

    enum Target: String, CaseIterable, Hashable {
        case drawThings
        case diffusionBee

        var displayName: String {
            switch self {
            case .drawThings: return "Draw Things"
            case .diffusionBee: return "DiffusionBee"
            }
        }

        /// Bundle names to look for under `/Applications` and `~/Applications`.
        /// DiffusionBee's display bundle is "Diffusion Bee.app" with a space;
        /// the no-space form is included for completeness.
        var bundleNames: [String] {
            switch self {
            case .drawThings: return ["Draw Things"]
            case .diffusionBee: return ["Diffusion Bee", "DiffusionBee"]
            }
        }
    }

    // MARK: Sending

    enum SendResult: Equatable {
        case launched(Target)
        case appNotFound(Target)
    }

    /// Copies the prompt to the system pasteboard and brings the target app
    /// to the foreground. Always copies, even if the app isn't installed —
    /// the user can paste it elsewhere.
    @discardableResult
    static func send(prompt: String, to target: Target) -> SendResult {
        copyToClipboard(prompt)
        guard let url = locate(target) else { return .appNotFound(target) }
        NSWorkspace.shared.open(url)
        return .launched(target)
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Returns the on-disk URL of the target app, or nil if it isn't
    /// installed in `/Applications` or `~/Applications`. Apps installed in
    /// non-standard locations won't be found; in that case the prompt is
    /// still copied to the clipboard.
    static func locate(_ target: Target) -> URL? {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        for root in roots {
            for name in target.bundleNames {
                let path = "\(root)/\(name).app"
                if fm.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }
}
