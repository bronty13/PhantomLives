import Foundation
import SwiftUI

/// Tab-completion state carried alongside the live input string. Captured
/// at the moment Tab is first pressed so subsequent Tabs cycle through
/// the same candidate pool without re-deriving it.
///
/// Lifted to a top-level type in 1.0.238 when `BufferInputState` was
/// extracted out of `BufferView` — was previously nested inside
/// `BufferView` as `BufferView.TabCompletion`. The shape is unchanged.
struct TabCompletion {
    /// Text before the completed word — includes the trailing space when
    /// the completion lands mid-line, empty when completing the very
    /// first word.
    let typedPrefix: String
    /// The partial the user originally typed (before pressing Tab).
    /// Kept so the cycle stays anchored to the prefix even after the
    /// input is rewritten to the candidate plus its suffix.
    let partial: String
    /// Sorted matching candidates (nicks, channels, or slash commands).
    let candidates: [String]
    /// Index into `candidates` of the entry currently inserted.
    var index: Int
    /// Trailing punctuation appended after the candidate — `": "` for
    /// the first word of an empty line (nick-mention shape), `" "`
    /// otherwise.
    let suffix: String
}

/// Per-`BufferView` input-bar state — the text the user is typing, the
/// history buffer (↑/↓), the active tab-completion cycle, and the
/// scratch flag for the slash-picker dismiss-by-Esc behaviour.
///
/// Extracted from `BufferView` in 1.0.238 so the parent's `@State`
/// cluster doesn't span the entire chat-area surface. The parent
/// holds one `@StateObject` instance which is preserved across
/// buffer switches (same shape as the prior `@State` properties did
/// before — BufferView's identity is keyed by view position, not by
/// `bufferIndex`, so switching channels does not reset the input).
///
/// Methods on this class are the only places the history array is
/// trimmed (`maxHistory`) or the position is bumped — keeping the
/// invariants in one place removed duplication that lived at three
/// call sites in `BufferView` (`sendInput`, `sendDraft`, history nav).
@MainActor
final class BufferInputState: ObservableObject {
    /// Live text in the input TextField. Bound directly via `$input`.
    @Published var input: String = ""
    /// Rolling history of sent lines, oldest first. Capped at
    /// `maxHistory`; older entries are dropped from the front on
    /// insert so the cap is never exceeded.
    @Published var history: [String] = []
    /// Cursor into `history` for ↑/↓ navigation. `history.count`
    /// means "past the end" (i.e. the user is composing a fresh line,
    /// not browsing).
    @Published var historyPos: Int = 0
    /// Active tab-completion cycle. nil means "no completion in
    /// progress"; Tab starts a fresh cycle.
    @Published var completion: TabCompletion? = nil
    /// Input string at the moment the user pressed Esc on the
    /// slash-command picker — the picker stays dismissed until the
    /// input shape changes. Reset whenever the input is replaced by
    /// non-Esc means.
    @Published var pickerDismissedFor: String? = nil

    /// Maximum number of sent lines retained in `history`. Older
    /// entries fall off the front as new ones land.
    static let maxHistory = 200

    /// Append a sent line to history, capping at `maxHistory`, and
    /// reset `historyPos` to past-the-end so the next ↑ starts at the
    /// just-sent line.
    func pushHistory(_ text: String) {
        history.append(text)
        if history.count > Self.maxHistory {
            history.removeFirst(history.count - Self.maxHistory)
        }
        historyPos = history.count
    }

    /// Walk one step backwards in history. Returns the new input
    /// string to load, or nil when already at the oldest entry.
    func historyPrev() -> String? {
        guard !history.isEmpty, historyPos > 0 else { return nil }
        historyPos -= 1
        return history[historyPos]
    }

    /// Walk one step forwards. Returns the new input string to load,
    /// which is "" when stepping past the most recent entry (back to
    /// composing a fresh line).
    func historyNext() -> String {
        if historyPos < history.count - 1 {
            historyPos += 1
            return history[historyPos]
        }
        historyPos = history.count
        return ""
    }
}
