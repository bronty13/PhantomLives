import Foundation

/// A bundled writing prompt. Pure static content — no network, nothing
/// generated. Categories are for flavor/grouping only.
struct Prompt: Codable, Hashable, Identifiable {
    var category: String
    var text: String
    var id: String { text }
}

/// Loads the bundled `Prompts.json` library and rotates through it on-device.
/// Selection is deterministic per calendar day (so "today's prompt" is stable
/// across relaunches) with a cycle helper for the editor's shuffle button.
enum PromptService {

    /// The prompt library, loaded once from the app bundle. Falls back to a
    /// single safe prompt if the resource is missing (e.g. under XCTest, whose
    /// bundle doesn't carry the app resources).
    static let all: [Prompt] = loadFromBundle()

    static let fallback = Prompt(category: "Open", text: "What's on your mind right now?")

    static func loadFromBundle() -> [Prompt] {
        guard let url = Bundle.main.url(forResource: "Prompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let prompts = try? JSONDecoder().decode([Prompt].self, from: data),
              !prompts.isEmpty else { return [fallback] }
        return prompts
    }

    /// Deterministic index for a given day ordinal across a library of `count`.
    /// Pure — the unit of testable behavior.
    static func dailyIndex(dayOrdinal: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((dayOrdinal % count) + count) % count
    }

    /// Today's prompt from `prompts`, stable for the calendar day of `date`.
    static func prompt(for date: Date, from prompts: [Prompt], calendar: Calendar = .current) -> Prompt {
        guard !prompts.isEmpty else { return fallback }
        let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return prompts[dailyIndex(dayOrdinal: ordinal, count: prompts.count)]
    }

    /// Convenience over the bundled library.
    static func prompt(for date: Date, calendar: Calendar = .current) -> Prompt {
        prompt(for: date, from: all, calendar: calendar)
    }

    /// The prompt after `current` in the library — backs the editor's shuffle.
    static func next(after current: Prompt, in prompts: [Prompt] = all) -> Prompt {
        guard !prompts.isEmpty else { return fallback }
        guard let idx = prompts.firstIndex(of: current) else { return prompts[0] }
        return prompts[(idx + 1) % prompts.count]
    }
}
