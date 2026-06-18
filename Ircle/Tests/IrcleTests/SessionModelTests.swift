import Foundation
import Testing
import IRCKit
@testable import Ircle

@MainActor
@Suite("IrcleBuffer + nick list")
struct IrcleBufferTests {

    @Test func addsAndDedupesUsersWithPrefixes() {
        let b = IrcleBuffer(kind: .channel, name: "#test")
        b.addUser("@alice")
        b.addUser("+bob")
        b.addUser("carol")
        #expect(b.users.count == 3)
        // Re-adding with a different prefix updates, doesn't duplicate.
        b.addUser("alice")          // bare — folds to same id
        #expect(b.users.count == 3)
        #expect(b.hasUser("ALICE")) // case-insensitive
    }

    @Test func sortsOpsAboveVoiceAbovePlain() {
        let b = IrcleBuffer(kind: .channel, name: "#test")
        b.addUser("zeke")           // plain
        b.addUser("+yara")          // voice
        b.addUser("@xavier")        // op
        #expect(b.users.map(\.nick) == ["xavier", "yara", "zeke"])
    }

    @Test func removeAndRename() {
        let b = IrcleBuffer(kind: .channel, name: "#test")
        b.addUser("@alice")
        b.addUser("bob")
        b.removeUser("BOB")
        #expect(b.users.count == 1)
        b.renameUser(from: "alice", to: "alice2")
        #expect(b.users.first?.nick == "alice2")
    }

    @Test func unreadAccountingSkipsFocusedBuffer() {
        let b = IrcleBuffer(kind: .channel, name: "#test")
        b.append(IrcleLine(kind: .message, sender: "x", text: "hi"), focused: false)
        b.append(IrcleLine(kind: .message, sender: "x", text: "yo", isMention: true), focused: false)
        #expect(b.unread == 2)
        #expect(b.mentioned)
        b.clearUnread()
        #expect(b.unread == 0)
        #expect(!b.mentioned)
        b.append(IrcleLine(kind: .message, sender: "x", text: "again"), focused: true)
        #expect(b.unread == 0) // focused → not counted
    }

    @Test func scrollbackIsCapped() {
        let b = IrcleBuffer(kind: .channel, name: "#test")
        for i in 0..<(IrcleBuffer.maxLines + 50) {
            b.append(IrcleLine(kind: .message, sender: "x", text: "\(i)"), focused: true)
        }
        #expect(b.lines.count == IrcleBuffer.maxLines)
        // Oldest lines dropped; the last line is the most recent.
        #expect(b.lines.last?.text == "\(IrcleBuffer.maxLines + 49)")
    }
}

@MainActor
@Suite("IrcleUser ordering")
struct IrcleUserTests {
    @Test func rankThenNameOrder() {
        let users = [
            IrcleUser(nick: "bob", prefix: ""),
            IrcleUser(nick: "amy", prefix: "@"),
            IrcleUser(nick: "cara", prefix: "+"),
            IrcleUser(nick: "abe", prefix: "@"),
        ].sorted()
        #expect(users.map(\.nick) == ["abe", "amy", "cara", "bob"])
    }

    @Test func caseFolding() {
        #expect(IRCCase.equal("#Chan", "#chan"))
        #expect(IRCCase.equal("Nick", "nick"))
        #expect(!IRCCase.equal("a", "b"))
    }
}

@MainActor
@Suite("IrcleSession plumbing")
struct IrcleSessionTests {

    private func makeSession() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    @Test func startsWithServerBufferSelected() {
        let s = makeSession()
        #expect(s.buffers.count == 1)
        #expect(s.buffers.first?.kind == .server)
        #expect(s.nick == "me")
    }

    @Test func ensureQueryIsCaseInsensitiveAndDeduped() {
        let s = makeSession()
        let q1 = s.ensureQuery("Alice")
        let q2 = s.ensureQuery("alice")
        #expect(q1 === q2)
        #expect(s.buffers.contains { $0.kind == .query })
    }

    @Test func sendTextOnServerBufferIsRejected() {
        let s = makeSession()
        s.sendText("hello", to: s.serverBuffer)
        // The rejection note lands as a system line in the server console.
        #expect(s.serverBuffer.lines.contains { $0.kind == .system })
    }

    @Test func sendTextEchoesLocallyWhenDisconnected() {
        let s = makeSession()
        let q = s.ensureQuery("bob")
        s.sendText("hi bob", to: q)
        // Not connected ⇒ no echo-message cap ⇒ we echo locally.
        #expect(q.lines.contains { $0.kind == .message && $0.isSelf && $0.text == "hi bob" })
    }

    @Test func closingAQueryRemovesIt() {
        let s = makeSession()
        let q = s.ensureQuery("bob")
        s.closeBuffer(q)
        #expect(!s.buffers.contains { $0.id == q.id })
    }
}
