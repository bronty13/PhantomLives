import Foundation
import Testing
@testable import SlackSucker

/// Tests for the pure pieces of the runner pipeline: LineBuffer,
/// RunStats, PATH augmentation, and the parsers that turn slackdump's
/// text-mode output into structured records.

@Suite("LineBuffer")
struct LineBufferTests {

    @Test("handles CRLF and bare CR overwrite")
    func handlesCRLFAndBareCR() {
        let buf = LineBuffer()
        buf.append("hello\nworld\r\nprog\r".data(using: .utf8)!)
        let lines = buf.extractLines()
        #expect(lines.count == 3)
        #expect(lines[0].0 == "hello"); #expect(!lines[0].1)
        #expect(lines[1].0 == "world")
        #expect(lines[2].0 == "prog")

        buf.append("prog2\n".data(using: .utf8)!)
        let next = buf.extractLines()
        #expect(next.count == 1)
        #expect(next[0].0 == "prog2")
        #expect(next[0].1, "expected CR-overwrite flag after a bare CR")
    }

    @Test("drains trailing partial line")
    func drainsTrailing() {
        let buf = LineBuffer()
        buf.append("partial".data(using: .utf8)!)
        #expect(buf.extractLines().isEmpty)
        #expect(buf.drainTrailing() == ["partial"])
    }
}

@Suite("RunStats")
struct RunStatsTests {

    @Test("absorbs channel / message / file counts from text lines")
    func absorbsCounts() {
        var s = RunStats()
        s.absorb("Fetched 12 channels")
        s.absorb("Wrote 4321 messages")
        s.absorb("Downloaded 17 files")
        #expect(s.channelCount == 12)
        #expect(s.messageCount == 4321)
        #expect(s.fileCount == 17)
    }

    @Test("phase detection sticks until next matching line")
    func phaseDetection() {
        var s = RunStats()
        s.absorb("Fetching channels...")
        #expect(s.phase == "Fetching channels...")
        s.absorb("Downloading files (3/17)")
        #expect(s.phase == "Downloading files (3/17)")
        s.absorb("non-matching line")
        #expect(s.phase == "Downloading files (3/17)")
    }
}

@Suite("ArchiveRunner helpers")
struct ArchiveRunnerHelperTests {

    @Test("augmentedPATH includes homebrew and is idempotent")
    func augmentedPATHIdempotent() {
        let result = ArchiveRunner.augmentedPATH(existing: "/usr/bin:/bin")
        let parts = result.split(separator: ":").map(String.init)
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/usr/local/bin"))
        #expect(parts.contains("/usr/bin"))
        #expect(parts.contains("/bin"))

        let again = ArchiveRunner.augmentedPATH(existing: result)
        let unique = Set(again.split(separator: ":")).count
        let total = again.split(separator: ":").count
        #expect(unique == total, "PATH augmentation must be idempotent")
    }
}

@Suite("WorkspaceService parser")
struct WorkspaceParserTests {

    @Test("parses real slackdump v4 list output")
    func parseSlackdumpV4Format() {
        let stdout = """
        Workspaces in "/Users/me/Library/Caches/slackdump":

        => default (file: provider.bin, last modified: 2026-05-15 12:02:46)
           other   (file: provider2.bin, last modified: 2026-04-01 09:00:00)

        Current workspace is marked with ' => '.
        """
        let parsed = WorkspaceService.parseList(stdout)
        #expect(parsed.count == 2)
        #expect(parsed[0].name == "default")
        #expect(parsed[0].isCurrent)
        #expect(parsed[1].name == "other")
        #expect(!parsed[1].isCurrent)
    }

    @Test("ignores header and footer chrome")
    func ignoresChrome() {
        let stdout = """
        Workspaces in "/tmp":

        Current workspace is marked with ' => '.
        """
        let parsed = WorkspaceService.parseList(stdout)
        #expect(parsed.isEmpty)
    }

    @Test("detects overwrite prompt and extracts workspace name")
    func detectOverwritePrompt() {
        let line = #"Workspace "default" already exists. Overwrite? (y/N)"#
        #expect(WorkspaceService.detectOverwritePrompt(in: line) == "default")
        // Unrelated lines must not trigger the prompt.
        #expect(WorkspaceService.detectOverwritePrompt(in: "Fetching channels...") == nil)
    }
}

@Suite("ChannelService JSON parser")
struct ChannelParserTests {

    /// Real fixture pulled from `slackdump list channels -format JSON`
    /// against the maintainer's live workspace, then minified to the
    /// fields the parser cares about. The full document has many more
    /// keys (image URLs, locales, etc.) that JSONDecoder must tolerate.
    private static let channelsJSON = """
    [
      {"id":"C0B3LV2284F","name":"social","is_im":false,"is_mpim":false,
       "is_private":false,"is_archived":false,
       "purpose":{"value":"Other channels are for work. This one is just for fun.","creator":"","last_set":0}},
      {"id":"C0B3W691QKV","name":"coc-content","is_im":false,"is_mpim":false,
       "is_private":true,"is_archived":false,
       "purpose":{"value":"","creator":"","last_set":0}},
      {"id":"C0OLD0000","name":"archived-channel","is_im":false,"is_mpim":false,
       "is_private":false,"is_archived":true,
       "purpose":{"value":"","creator":"","last_set":0}},
      {"id":"D0B461SN78U","name":"","is_im":true,"is_mpim":false,
       "user":"USLACKBOT","is_archived":false},
      {"id":"D0B40BZ1YS2","name":"","is_im":true,"is_mpim":false,
       "user":"U0B462P7G9J","is_archived":false},
      {"id":"GMPDM0000","name":"alice--bob--carol","is_im":false,"is_mpim":true,
       "is_archived":false}
    ]
    """

    private static let usersJSON = """
    [
      {"id":"U0B462P7G9J","name":"princessofrealaddicti","real_name":"Sallie",
       "deleted":false,"is_bot":false,
       "profile":{"display_name":"","real_name":"Sallie",
                  "email":"princessofrealaddiction@gmail.com"}},
      {"id":"U0B4WMERTUG","name":"amazingrobert","real_name":"Robert Olen",
       "deleted":false,"is_bot":false,
       "profile":{"display_name":"rob","email":"robert@example.com"}},
      {"id":"USLACKBOT","name":"slackbot","real_name":"Slackbot",
       "deleted":false,"is_bot":false,
       "profile":{"display_name":""}},
      {"id":"UDELETED","name":"ghost","real_name":"Ghost",
       "deleted":true,"is_bot":false}
    ]
    """

    @Test("decodes channels JSON, classifies private + filters archived")
    func decodeChannels() throws {
        let rows = try ChannelService.decodeJSONArray(Self.channelsJSON,
                                                     as: ChannelService.RawChannel.self)
        #expect(rows.count == 6)
        #expect(rows[0].id == "C0B3LV2284F")
        #expect(rows[0].is_private == false)
        #expect(rows[1].is_private == true)
        #expect(rows[3].is_im == true)
        #expect(rows[3].user == "USLACKBOT")
        #expect(rows[5].is_mpim == true)
    }

    @Test("merge produces flat entity list with correct kinds + display names")
    func mergeProducesEntities() throws {
        let channels = try ChannelService.decodeJSONArray(Self.channelsJSON,
                                                         as: ChannelService.RawChannel.self)
        let users    = try ChannelService.decodeJSONArray(Self.usersJSON,
                                                         as: ChannelService.RawUser.self)
        let merged = ChannelService.merge(rawChannels: channels, rawUsers: users)

        // 6 channels - 1 archived = 5 channels/dms/mpdm
        // 4 users    - 1 deleted = 3 users
        #expect(merged.count == 8)

        // Public channel: "#social"
        let social = merged.first { $0.id == "C0B3LV2284F" }
        #expect(social?.name == "#social")
        #expect(social?.kind == .channel)
        #expect(social?.subtitle == "Other channels are for work. This one is just for fun.")

        // Private channel: prefixed with lock glyph
        let coc = merged.first { $0.id == "C0B3W691QKV" }
        #expect(coc?.name == "🔒 coc-content")
        #expect(coc?.kind == .channel)

        // DM with resolvable user → uses display_name when set ("rob"),
        // else real_name ("Sallie")
        let dmRobert = merged.first { $0.id == "D0B40BZ1YS2" }
        #expect(dmRobert?.name == "@Sallie")
        #expect(dmRobert?.kind == .dm)
        #expect(dmRobert?.subtitle == "princessofrealaddiction@gmail.com")

        // DM with slackbot
        let dmBot = merged.first { $0.id == "D0B461SN78U" }
        #expect(dmBot?.name == "@Slackbot")
        #expect(dmBot?.kind == .dm)

        // MPDM gets a "(group)" prefix
        let mpdm = merged.first { $0.id == "GMPDM0000" }
        #expect(mpdm?.kind == .mpdm)
        #expect(mpdm?.name == "(group) alice--bob--carol")

        // User row: preferredName prefers display_name → "rob"
        let userRobert = merged.first { $0.id == "U0B4WMERTUG" }
        #expect(userRobert?.name == "rob")
        #expect(userRobert?.kind == .user)
        #expect(userRobert?.subtitle == "robert@example.com")

        // Archived channel must be excluded
        #expect(!merged.contains { $0.id == "C0OLD0000" })
        // Deleted user must be excluded
        #expect(!merged.contains { $0.id == "UDELETED" })
    }

    @Test("decodeJSONArray tolerates trailing text after array")
    func decodeJSONArrayTolerant() throws {
        // Real-world drift the decoder must absorb: a stray newline +
        // log line *after* the JSON array. (Pre-array noise can't
        // begin with `[` — slackdump's logger goes to stderr in
        // -format JSON mode, so this is the only realistic shape.)
        let noisy = """
        [{"id":"C123","name":"foo","is_im":false,"is_mpim":false,"is_archived":false,"is_private":false}]
        trailing log line
        """
        let rows = try ChannelService.decodeJSONArray(noisy, as: ChannelService.RawChannel.self)
        #expect(rows.count == 1)
        #expect(rows[0].id == "C123")
    }

    @Test("decodeJSONArray returns empty for non-JSON input")
    func decodeJSONArrayEmpty() throws {
        let rows = try ChannelService.decodeJSONArray("not json at all",
                                                     as: ChannelService.RawChannel.self)
        #expect(rows.isEmpty)
    }
}
