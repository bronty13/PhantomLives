import Foundation

/// Seeds a handful of sample entries on first launch so the app isn't an empty
/// void for a new user. One-shot: gated by `sampleDataEverInstalled` so a later
/// delete isn't silently undone. An explicit "Restore Sample Data" button in
/// Settings → General re-adds them.
@MainActor
enum SampleDataService {

    /// Installs samples iff this is the first run AND the journal is empty.
    /// Returns true if anything was inserted (caller should reload).
    @discardableResult
    static func installIfFirstRunCompleted(existing entries: [Entry], settingsStore: SettingsStore) -> Bool {
        guard !settingsStore.settings.sampleDataEverInstalled else { return false }
        // Flip the flag regardless, so we never re-seed even if the user
        // immediately deletes the samples.
        var s = settingsStore.settings
        s.sampleDataEverInstalled = true
        settingsStore.settings = s
        settingsStore.save()

        guard entries.isEmpty else { return false }
        return restoreSamples()
    }

    /// Unconditionally insert the sample entries. Wired to the
    /// Settings → General "Restore Sample Data" button.
    @discardableResult
    static func restoreSamples() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let samples: [(daysAgo: Int, title: String, body: String, mood: Mood)] = [
            (0, "A fresh start",
             "Set up **PurpleDiary** today. The idea: one place that's just mine — no account, no cloud unless I say so. Wrote this first entry to see how the editor feels.",
             .good),
            (2, "Long walk by the water",
             "Took the afternoon off and walked the loop trail. The light on the water was unreal. Felt my shoulders drop about halfway round. Want more days like this.",
             .great),
            (5, "Rough one",
             "Tough day at work — the deploy slipped again and I let it get to me more than it deserved. Note to self: it's a Tuesday, not a verdict on my whole life.",
             .bad),
            (9, "Small wins",
             "- Finally fixed the thing that's been nagging me for a week\n- Called Mom\n- Cooked instead of ordering in\n\nNone of it is dramatic but it adds up.",
             .okay),
        ]

        var inserted = false
        for sample in samples {
            let date = cal.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
            var entry = Entry.newDraft(date: date, title: sample.title)
            entry.bodyMarkdown = sample.body
            entry.mood = sample.mood
            do {
                try DatabaseService.shared.insertEntry(entry)
                inserted = true
            } catch {
                NSLog("PurpleDiary: failed to seed sample entry — \(error.localizedDescription)")
            }
        }
        return inserted
    }
}
