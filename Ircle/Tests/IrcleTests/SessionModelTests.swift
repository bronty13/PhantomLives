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

/// Drives the core inbound dispatch with synthetic server lines (no socket) —
/// the path that actually makes Ircle an IRC client: IRCMessage.parse → handle
/// → buffers. Also exercises IRCKit's parser end-to-end through the session.
@MainActor
@Suite("IrcleSession inbound dispatch")
struct IrcleSessionDispatchTests {

    private func connected(nick: String = "me") -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: nick, user: nick, realName: nick)
        return IrcleSession(config: cfg, displayName: "Example")
    }

    private func channel(_ s: IrcleSession, _ name: String) -> IrcleBuffer? {
        s.buffers.first { $0.kind == .channel && IRCCase.equal($0.name, name) }
    }

    @Test func selfJoinCreatesChannelAndNamesPopulatesNickList() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        #expect(channel(s, "#x") != nil)
        s.ingest(":srv 353 me = #x :alice @bob +carol")
        s.ingest(":srv 366 me #x :End of /NAMES")
        let chan = channel(s, "#x")!
        #expect(chan.users.count == 3)
        // bob is op (@) → ranks above voiced carol and plain alice.
        #expect(chan.users.first?.nick == "bob")
        #expect(chan.users.contains { $0.nick == "carol" && $0.prefix == "+" })
    }

    @Test func privmsgFromOtherLandsInChannelWithSender() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":bob!u@h PRIVMSG #x :hello there")
        let chan = channel(s, "#x")!
        let line = chan.lines.first { $0.kind == .message }
        #expect(line?.sender == "bob")
        #expect(line?.text == "hello there")
        #expect(line?.isSelf == false)
    }

    @Test func mentionOfOurNickIsFlagged() {
        let s = connected(nick: "ircle-user")
        s.ingest(":ircle-user!u@h JOIN #x")
        s.ingest(":bob!u@h PRIVMSG #x :hey ircle-user how are you")
        let line = channel(s, "#x")!.lines.first { $0.kind == .message }
        #expect(line?.isMention == true)
    }

    @Test func actionRendersAsActionLine() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":bob!u@h PRIVMSG #x :\u{01}ACTION waves\u{01}")
        let line = channel(s, "#x")!.lines.first { $0.kind == .action }
        #expect(line?.sender == "bob")
        #expect(line?.text == "waves")
    }

    @Test func topicNumericSetsChannelTopic() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":srv 332 me #x :welcome to the channel")
        #expect(channel(s, "#x")?.topic == "welcome to the channel")
    }

    @Test func partRemovesUserAndQuitSweepsAllChannels() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":srv 353 me = #x :@bob alice")
        s.ingest(":alice!u@h PART #x :bye")
        #expect(channel(s, "#x")?.hasUser("alice") == false)
        #expect(channel(s, "#x")?.hasUser("bob") == true)
        s.ingest(":bob!u@h QUIT :leaving")
        #expect(channel(s, "#x")?.hasUser("bob") == false)
    }

    @Test func incomingPrivateMessageOpensQueryKeyedBySender() {
        let s = connected()
        s.ingest(":dave!u@h PRIVMSG me :psst")
        let q = s.buffers.first { $0.kind == .query }
        #expect(q?.name == "dave")
        #expect(q?.lines.first { $0.kind == .message }?.text == "psst")
    }

    @Test func nickChangeRenamesAcrossChannels() {
        let s = connected()
        s.ingest(":me!u@h JOIN #x")
        s.ingest(":srv 353 me = #x :bob")
        s.ingest(":bob!u@h NICK bobby")
        #expect(channel(s, "#x")?.hasUser("bobby") == true)
        #expect(channel(s, "#x")?.hasUser("bob") == false)
    }

    @Test func nickInUseAutoBumpsDuringRegistration() {
        // Pre-001 (not yet registered): a 433 must bump the nick so registration
        // can complete — the bug that left a second connection stuck.
        let s = connected(nick: "bob")
        s.ingest(":srv 433 * bob :Nickname is already in use")
        #expect(s.nick == "bob_")
        s.ingest(":srv 433 * bob_ :Nickname is already in use")
        #expect(s.nick == "bob__")
    }

    @Test func nickInUseDoesNotBumpAfterRegistration() {
        let s = connected(nick: "bob")
        s.ingest(":srv 001 bob :Welcome")     // registered
        s.ingest(":srv 433 * bob :Nickname is already in use")
        #expect(s.nick == "bob")              // no auto-bump once registered
    }
}
