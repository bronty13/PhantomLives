import Foundation
import Testing
@testable import PurpleIRC

/// Coverage for `BufferView.groupRows` — the join/part/quit/nick collapse
/// algorithm (flushRun, 300s window, single-event suppression) the audit
/// flagged as untested.
@Suite("BufferView row grouping")
struct BufferGroupingTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func line(_ kind: ChatLine.Kind, at offset: TimeInterval) -> ChatLine {
        ChatLine(timestamp: base.addingTimeInterval(offset), kind: kind, text: "")
    }

    @Test func collapseOffKeepsEveryLineRaw() {
        let lines = [line(.join(nick: "a"), at: 0), line(.join(nick: "b"), at: 1)]
        let rows = BufferView.groupRows(lines, collapse: false)
        #expect(rows.count == 2)
        for r in rows {
            if case .summary = r { Issue.record("did not expect a summary when collapse is off") }
        }
    }

    @Test func runOfThreeCollapsesToOneSummary() {
        let lines = [
            line(.join(nick: "a"), at: 0),
            line(.join(nick: "b"), at: 1),
            line(.part(nick: "c", reason: nil), at: 2),
        ]
        let rows = BufferView.groupRows(lines, collapse: true)
        #expect(rows.count == 1)
        guard case .summary(_, let entries) = rows.first else {
            Issue.record("expected a summary row"); return
        }
        #expect(entries.count == 3)
    }

    @Test func singleMembershipEventStaysRawLine() {
        let rows = BufferView.groupRows([line(.join(nick: "a"), at: 0)], collapse: true)
        #expect(rows.count == 1)
        guard case .line = rows.first else {
            Issue.record("a one-event run should render as the raw line, not a summary"); return
        }
    }

    @Test func nonMembershipLineBreaksTheRun() {
        // join, join, privmsg, join → summary(2) · line(privmsg) · line(join)
        let lines = [
            line(.join(nick: "a"), at: 0),
            line(.join(nick: "b"), at: 1),
            line(.privmsg(nick: "x", isSelf: false), at: 2),
            line(.join(nick: "c"), at: 3),
        ]
        let rows = BufferView.groupRows(lines, collapse: true)
        #expect(rows.count == 3)
        guard case .summary(_, let entries) = rows[0], entries.count == 2 else {
            Issue.record("first row should summarise the 2-join run"); return
        }
        if case .summary = rows[1] { Issue.record("privmsg must stay a raw line") }
        if case .summary = rows[2] { Issue.record("trailing single join must stay a raw line") }
    }

    @Test func gapBeyondWindowDoesNotGroup() {
        // Two joins 400s apart — outside the 300s window, so each stands alone.
        let lines = [line(.join(nick: "a"), at: 0), line(.join(nick: "b"), at: 400)]
        let rows = BufferView.groupRows(lines, collapse: true)
        #expect(rows.count == 2)
        for r in rows {
            if case .summary = r { Issue.record("events outside the window must not be grouped") }
        }
    }
}
