import Foundation
import Testing
@testable import SlackSucker

/// Argv-builder tests. The slackdump CLI parses positional arguments
/// strictly, so any drift in flag ordering or omission would surface
/// here before it lands in the field.

@Suite("ArchiveRequest")
struct ArchiveRequestTests {

    private func iso(_ s: String) -> Date {
        ArchiveRequest.formatter.date(from: s)!
    }

    private let outDir = URL(fileURLWithPath: "/tmp/ss-test/run", isDirectory: true)

    @Test("entire workspace, all time -> only -o")
    func entireWorkspaceAllTime() {
        let req = ArchiveRequest(
            workspace: nil,
            scope: .entireWorkspace,
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: false,
            outputDir: outDir
        )
        #expect(req.argumentList() == ["archive", "-o", outDir.path])
    }

    @Test("channel by ID with time range")
    func channelByIDWithTimeRange() {
        let from = iso("2026-04-01T00:00:00")
        let to   = iso("2026-05-01T00:00:00")
        let req = ArchiveRequest(
            workspace: "my-workspace",
            scope: .channel(idOrURL: "C0123ABC", displayName: "general"),
            timeRange: .range(from: from, to: to),
            includeFiles: true,
            includeAvatars: true,
            memberOnly: false,
            outputDir: outDir
        )
        #expect(req.argumentList() == [
            "archive",
            "-workspace", "my-workspace",
            "-o", outDir.path,
            "-avatars",
            "-time-from", "2026-04-01T00:00:00",
            "-time-to",   "2026-05-01T00:00:00",
            "C0123ABC"
        ])
    }

    @Test("DM by URL with files disabled")
    func dmByURLFilesDisabled() {
        let url = "https://my.slack.com/archives/DABCDEFG"
        let req = ArchiveRequest(
            workspace: nil,
            scope: .dm(idOrURL: url, displayName: nil),
            timeRange: .all,
            includeFiles: false,
            includeAvatars: false,
            memberOnly: false,
            outputDir: outDir
        )
        #expect(req.argumentList() == [
            "archive",
            "-o", outDir.path,
            "-files=false",
            url
        ])
    }

    @Test("member-only flag, workspace-wide")
    func memberOnlyWorkspaceWide() {
        let req = ArchiveRequest(
            workspace: nil,
            scope: .entireWorkspace,
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: true,
            outputDir: outDir
        )
        #expect(req.argumentList() == [
            "archive", "-o", outDir.path, "-member-only"
        ])
    }

    @Test("thread URL rewrites to channel + ±1s time bracket")
    func threadURLRewritesToChannelBracket() {
        // 1700000000.123456 → 2023-11-14 22:13:20 UTC. The bracket
        // emitted is parent_TS ± 1s, formatted as UTC YYYY-MM-DDTHH:MM:SS.
        let url = "https://my.slack.com/archives/C123/p1700000000123456"
        let req = ArchiveRequest(
            workspace: nil,
            scope: .threadURL(url),
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: false,
            outputDir: outDir
        )
        #expect(req.argumentList() == [
            "archive",
            "-o", outDir.path,
            "-time-from", "2023-11-14T22:13:19",
            "-time-to",   "2023-11-14T22:13:21",
            "C123"
        ])
    }

    @Test("malformed thread URL falls back to passing the raw string")
    func threadURLMalformedFallsBack() {
        let url = "https://not-a-real-permalink/whatever"
        let req = ArchiveRequest(
            workspace: nil,
            scope: .threadURL(url),
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: false,
            outputDir: outDir
        )
        // Can't parse → fall through to the generic path that just
        // passes the URL through. Better to surface slackdump's own
        // error than to silently drop the request.
        #expect(req.argumentList() == [
            "archive", "-o", outDir.path, url
        ])
    }

    @Test("parseThreadURL extracts channel + TS")
    func parseThreadURLExtracts() {
        let parsed = ArchiveScope.parseThreadURL(
            "https://acme.slack.com/archives/C0B476GMXNG/p1778857781109479")
        #expect(parsed?.channelID == "C0B476GMXNG")
        #expect(parsed?.threadTSString == "1778857781.109479")
        #expect(parsed?.threadTSSeconds == 1778857781)

        #expect(ArchiveScope.parseThreadURL("not a url") == nil)
        #expect(ArchiveScope.parseThreadURL(
            "https://acme.slack.com/archives/Cabc/no-p-prefix") == nil)
    }

    @Test("debug flag emits -v")
    func debugFlagAppendsVerbose() {
        let req = ArchiveRequest(
            workspace: nil,
            scope: .entireWorkspace,
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: false,
            outputDir: outDir,
            debug: true
        )
        #expect(req.argumentList().contains("-v"))
    }

    @Test("scope slug is filesystem-safe")
    func scopeSlugIsFilesystemSafe() {
        let scope: ArchiveScope = .channel(idOrURL: "C123", displayName: "team / #urgent")
        #expect(!scope.slug.contains("/"))
        #expect(!scope.slug.contains(" "))
        #expect(scope.slug.count <= 40)
    }

    @Test("computeRunFolder embeds scope and timestamp")
    func computeRunFolderEmbedsScope() {
        let root = URL(fileURLWithPath: "/tmp/ss-root", isDirectory: true)
        let folder = ArchiveRequest.computeRunFolder(
            root: root,
            scope: .channel(idOrURL: "C123", displayName: "general")
        )
        #expect(folder.path.hasPrefix("/tmp/ss-root/general_"))
    }
}
