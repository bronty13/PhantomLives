import Foundation
import Testing
@testable import SlackSucker

@Suite("ChatExporter")
struct ChatExporterTests {

    private func msg(id: Int64,
                     ts: String,
                     user: String,
                     text: String?,
                     parent: Int64? = nil,
                     channel: String = "C0B3LV2284F",
                     isParent: Int = 0) -> ChatExporter.MessageRow {
        return ChatExporter.MessageRow(
            ID: id, TS: ts, CHANNEL_ID: channel,
            PARENT_ID: parent, THREAD_TS: nil,
            IS_PARENT: isParent, TXT: text, USER: user
        )
    }

    private static let users: [ChatExporter.UserRow] = [
        ChatExporter.UserRow(ID: "U001", USERNAME: "amazingrobert",
                             REAL_NAME: "Robert", DISPLAY_NAME: "rob"),
        ChatExporter.UserRow(ID: "U002", USERNAME: "princess",
                             REAL_NAME: "Sallie", DISPLAY_NAME: nil),
        ChatExporter.UserRow(ID: "U003", USERNAME: "slackbot",
                             REAL_NAME: "Slackbot", DISPLAY_NAME: nil),
    ]

    @Test("formats messages chronologically with thread replies indented")
    func formatsThreads() {
        let messages: [ChatExporter.MessageRow] = [
            msg(id: 1, ts: "1700000000.000000", user: "U001",
                text: "Hello team", isParent: 1),
            msg(id: 2, ts: "1700000010.000000", user: "U002",
                text: "Hi!", parent: 1),
            msg(id: 3, ts: "1700000020.000000", user: "U001",
                text: "Thanks", parent: 1),
            msg(id: 4, ts: "1700000100.000000", user: "U001",
                text: "Standalone message"),
        ]
        let body = ChatExporter.render(
            messages: messages,
            users: Self.users,
            files: [],
            channels: [],
            scopeLabel: "#general",
            workspace: "acme",
            runFolderName: "_general_20260515_120000"
        )

        #expect(body.contains("Scope: #general"))
        #expect(body.contains("Workspace: acme"))
        #expect(body.contains("@rob"))
        #expect(body.contains("@Sallie"))
        #expect(body.contains("Hello team"))
        // Thread replies are indented 4 spaces — the reply line starts
        // with `    [HH:MM:SS] @<who>`, NOT `    @<who>` directly. The
        // `] @Sallie` substring confirms the reply IS Sallie and the
        // 4-space prefix confirms the indent.
        let lines = body.split(separator: "\n").map(String.init)
        let replyLine = lines.first { $0.contains("] @Sallie") }
        #expect(replyLine?.hasPrefix("    ") == true,
                "thread reply must be indented 4 spaces")
        // Standalone message rendered at column 0
        #expect(body.contains("\n[") && body.contains("Standalone message"))
        // No trailing blank lines explosion
        #expect(!body.hasSuffix("\n\n\n"))
    }

    @Test("resolves <@U…> mentions to display names")
    func resolvesUserMentions() {
        let names = ["U0B462P7G9J": "Sallie", "U0B4WMERTUG": "rob"]
        let out = ChatExporter.resolveMentions(
            in: "<@U0B462P7G9J> joined the channel — cc <@U0B4WMERTUG>",
            userName: names)
        #expect(out == "@Sallie joined the channel — cc @rob")
    }

    @Test("resolves channel + URL mention shapes; decodes HTML entities")
    func resolvesChannelsAndLinks() {
        let names: [String: String] = [:]
        let out = ChatExporter.resolveMentions(
            in: "see <#C123|general> and <https://example.com/x?a=1&amp;b=2|docs>",
            userName: names)
        #expect(out.contains("#general"))
        #expect(out.contains("docs"))
        // The bare URL form: <https://x> → just the URL
        let bare = ChatExporter.resolveMentions(
            in: "<https://example.com>", userName: names)
        #expect(bare == "https://example.com")
        // amp/lt/gt entities decoded outside of <…> markup too
        let entities = ChatExporter.resolveMentions(
            in: "tom &amp; jerry &lt;3", userName: names)
        #expect(entities == "tom & jerry <3")
    }

    @Test("file attachments listed under their parent message")
    func filesAttached() {
        let messages = [
            msg(id: 42, ts: "1700000000.000000", user: "U001", text: "Here it is"),
        ]
        let files: [ChatExporter.FileRow] = [
            ChatExporter.FileRow(MESSAGE_ID: 42, FILENAME: "report.pdf", URL: nil),
            ChatExporter.FileRow(MESSAGE_ID: 42, FILENAME: "chart.png",  URL: nil),
            ChatExporter.FileRow(MESSAGE_ID: 999, FILENAME: "ignore.txt", URL: nil),
        ]
        let body = ChatExporter.render(
            messages: messages, users: Self.users, files: files, channels: [],
            scopeLabel: "DM", workspace: nil, runFolderName: "_dm")
        #expect(body.contains("[file] report.pdf"))
        #expect(body.contains("[file] chart.png"))
        // Files attached to other messages shouldn't leak in
        #expect(!body.contains("ignore.txt"))
    }

    @Test("unresolvable user IDs fall back to the raw ID, not crash")
    func unknownUserFallback() {
        let messages = [
            msg(id: 1, ts: "1700000000.000000",
                user: "U999UNKNOWN", text: "ghost message"),
        ]
        let body = ChatExporter.render(
            messages: messages, users: Self.users, files: [], channels: [],
            scopeLabel: "#x", workspace: nil, runFolderName: "_x")
        #expect(body.contains("@U999UNKNOWN"))
    }

    @Test("formatTimestamp converts Slack TS to local datetime string")
    func tsFormatting() {
        // 1700000000 → 2023-11-14 22:13:20 UTC. We display in local
        // time, so just assert the year + month + day prefix is right.
        let formatted = ChatExporter.formatTimestamp(ts: "1700000000.000000")
        #expect(formatted.hasPrefix("2023-11-14") || formatted.hasPrefix("2023-11-15"))
        // Garbage TS doesn't crash — returns the raw string
        #expect(ChatExporter.formatTimestamp(ts: "notats") == "notats")
    }
}
