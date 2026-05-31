import Foundation

/// Seeds sample entries and provides a bulk populate / remove facility
/// (Settings → General). Every entry the service creates has its id recorded in
/// `AppSettings.sampleDataIds`, so "Remove All Sample Entries" deletes exactly
/// what the app generated and never touches the user's own entries.
@MainActor
enum SampleDataService {

    /// Installs the canned samples iff this is the first run AND the journal is
    /// empty. Returns true if anything was inserted (caller should reload).
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
        return restoreSamples(settingsStore: settingsStore)
    }

    /// Insert the four canned sample entries. Wired to Settings → General's
    /// "Restore Sample Entries" button.
    @discardableResult
    static func restoreSamples(settingsStore: SettingsStore) -> Bool {
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

        var ids: [String] = []
        for sample in samples {
            let date = cal.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
            var entry = Entry.newDraft(date: date, title: sample.title)
            entry.bodyMarkdown = sample.body
            entry.mood = sample.mood
            do {
                try DatabaseService.shared.insertEntry(entry)
                ids.append(entry.id)
            } catch {
                NSLog("PurpleDiary: failed to seed sample entry — \(error.localizedDescription)")
            }
        }
        recordSampleIds(ids, settingsStore: settingsStore)
        return !ids.isEmpty
    }

    /// Bulk-generate `count` varied sample entries spread across the past ~120
    /// days. One write transaction. Returns the number inserted. Wired to
    /// Settings → General's "Add 100 Sample Entries" button.
    @discardableResult
    static func populate(count: Int = 100, settingsStore: SettingsStore) -> Int {
        guard count > 0 else { return 0 }
        let cal = Calendar.current
        let now = Date()
        let spanDays = 120

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for i in 0..<count {
            // Spread across the window, oldest first, with a little jitter so
            // multiple entries can land on the same day.
            let dayOffset = Int(Double(i) / Double(max(count - 1, 1)) * Double(spanDays))
            let hour = Int.random(in: 6...22)
            let minute = Int.random(in: 0...59)
            var date = cal.date(byAdding: .day, value: -(spanDays - dayOffset), to: now) ?? now
            date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date

            let (title, body) = Self.generatedContent(index: i)
            var entry = Entry.newDraft(date: date, title: title)
            entry.bodyMarkdown = body
            entry.mood = Mood(rawValue: Int.random(in: 0...5)) ?? .unset
            entries.append(entry)
        }

        do {
            try DatabaseService.shared.bulkInsertEntries(entries)
        } catch {
            NSLog("PurpleDiary: bulk sample insert failed — \(error.localizedDescription)")
            return 0
        }
        recordSampleIds(entries.map(\.id), settingsStore: settingsStore)
        return entries.count
    }

    /// Delete every entry the facility generated (tracked in `sampleDataIds`)
    /// and clear the list. Tolerant of ids the user already deleted by hand.
    @discardableResult
    static func removeAllSamples(settingsStore: SettingsStore) -> Int {
        let removed = (try? DatabaseService.shared.deleteEntries(ids: settingsStore.settings.sampleDataIds)) ?? 0
        var s = settingsStore.settings
        s.sampleDataIds = []
        settingsStore.settings = s
        settingsStore.save()
        return removed
    }

    // MARK: - Helpers

    private static func recordSampleIds(_ ids: [String], settingsStore: SettingsStore) {
        guard !ids.isEmpty else { return }
        var s = settingsStore.settings
        s.sampleDataIds.append(contentsOf: ids)
        settingsStore.settings = s
        settingsStore.save()
    }

    private static let titlePool = [
        "Morning pages", "A quiet day", "Notes to self", "Something good happened",
        "Working through it", "On the train", "Late night thoughts", "Weekend plans",
        "Gratitude list", "A small frustration", "Reading again", "Cooking experiment",
        "Phone call with a friend", "Trying to slow down", "Big idea", "Just checking in",
    ]
    private static let bodyPool = [
        "Today felt **lighter** than yesterday. I'm not sure why, but I'll take it.",
        "Three things I'm grateful for:\n- coffee that was actually hot\n- a walk between meetings\n- an early night",
        "Kept circling the same worry. Writing it down helped more than I expected.",
        "Made progress on the thing I'd been avoiding. *Momentum* is real.",
        "Rain all afternoon. Stayed in, read, didn't feel guilty about it.",
        "Talked to someone I hadn't spoken to in months. We picked up right where we left off.",
        "A reminder that **rest is productive too**. Trying to believe it.",
        "Small win: I closed the laptop at a reasonable hour for once.",
        "Felt scattered today. Tomorrow I'll pick one thing and actually finish it.",
        "The light at sunset was ridiculous. Stood at the window for a full minute.",
    ]

    private static func generatedContent(index: Int) -> (title: String, body: String) {
        let title = titlePool[index % titlePool.count]
        let body = bodyPool[(index / titlePool.count + index) % bodyPool.count]
        return (title, body)
    }
}
