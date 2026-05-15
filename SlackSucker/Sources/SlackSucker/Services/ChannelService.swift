import Foundation
import Combine

/// One row in the cached channel / user list. We keep both kinds together
/// because slackdump's `list` outputs them via parallel subcommands but
/// the picker doesn't care which side a row came from — DMs and channels
/// both surface as scope targets.
struct SlackEntity: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case channel
        case dm
        case mpdm
        case user
    }

    var id: String           // C…, D…, G…, U…
    var name: String         // "general", "Alex Schroeder", etc.
    var kind: Kind
    /// Soft display label (purpose / @handle) — what the type-ahead row
    /// shows in dimmer text under the name.
    var subtitle: String?
}

/// Wraps `slackdump list channels` / `list users` and caches the parsed
/// rows per-workspace at
///   ~/Library/Application Support/SlackSucker/channel-cache/<workspace>.json
///
/// The cache is best-effort: a stale cache is preferable to making the
/// user wait for a multi-second roundtrip every time they open the
/// scope picker. The "Refresh" button in the picker bypasses the cache.
@MainActor
final class ChannelService: ObservableObject {

    @Published private(set) var entities: [SlackEntity] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var cacheTimestamp: Date?

    private let binary: () -> String?
    private let cacheDir: URL

    init(binary: @escaping () -> String? = SlackdumpBinary.resolvedPath,
         cacheDir: URL = AppSupport.channelCacheDir) {
        self.binary = binary
        self.cacheDir = cacheDir
    }

    /// Load whatever's currently cached for this workspace into the
    /// published list. Cheap and synchronous — call on workspace change
    /// so the picker is populated before the user types.
    func loadCache(for workspace: String?) {
        let url = cacheURL(for: workspace)
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let snapshot = try? Self.decoder.decode(CacheSnapshot.self, from: data)
        else {
            entities = []
            cacheTimestamp = nil
            return
        }
        entities = snapshot.entities
        cacheTimestamp = snapshot.savedAt
    }

    /// Refresh the cache by shelling out to slackdump twice (channels
    /// and users). Caller awaits — the picker shows a spinner while
    /// `isLoading` is true.
    ///
    /// After fetch we merge the two lists: D-prefixed DM rows from the
    /// channel listing are matched against the user list so the picker
    /// shows "@robert" instead of "@<external>:U0B4WMERTUG".
    func refresh(for workspace: String?) async {
        guard !isLoading else { return }
        guard let bin = binary() else {
            lastError = "slackdump binary not found in app bundle."
            return
        }
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let workspaceArgs: [String] =
            (workspace?.isEmpty == false) ? ["-workspace", workspace!] : []

        // Capture errors from either fetch so a silent failure (wrong
        // workspace name, expired creds, missing binary) lands in
        // `lastError` instead of leaving the picker mysteriously empty.
        let rawChannels: [RawChannel]
        let rawUsers: [RawUser]
        do {
            async let channelsTask = try Self.runAndParseChannels(
                binary: bin, workspaceArgs: workspaceArgs)
            async let usersTask    = try Self.runAndParseUsers(
                binary: bin, workspaceArgs: workspaceArgs)
            rawChannels = try await channelsTask
            rawUsers    = try await usersTask
        } catch {
            lastError = "slackdump list failed: \(error.localizedDescription)"
            return
        }

        entities = Self.merge(rawChannels: rawChannels, rawUsers: rawUsers)
        cacheTimestamp = Date()
        persist(workspace: workspace)
    }

    /// Pure projection from the slackdump JSON shapes to our flattened
    /// `SlackEntity` model. Exposed for tests so the merge logic is
    /// unit-tested without spawning slackdump.
    nonisolated static func merge(rawChannels: [RawChannel],
                                  rawUsers: [RawUser]) -> [SlackEntity] {
        // Build a user-ID → display-name + email index once.
        var displayByID: [String: (name: String, email: String?)] = [:]
        var userEntities: [SlackEntity] = []
        for u in rawUsers {
            // Skip deleted accounts — they can't accept a DM archive
            // anyway, and including them just clutters the picker.
            if u.deleted == true { continue }
            let display = u.preferredName
            displayByID[u.id] = (display, u.profile?.email)
            userEntities.append(SlackEntity(
                id: u.id,
                name: display,
                kind: .user,
                subtitle: u.profile?.email
            ))
        }

        var channelEntities: [SlackEntity] = []
        for ch in rawChannels {
            if ch.is_archived == true { continue }

            if ch.is_im == true {
                // DM: the partner is `user`. Resolve to a friendly name
                // when we have it; fall back to the user ID.
                let partnerID = ch.user ?? ""
                let display = displayByID[partnerID]
                let name = "@" + (display?.name ?? (partnerID.isEmpty ? "unknown" : partnerID))
                channelEntities.append(SlackEntity(
                    id: ch.id,
                    name: name,
                    kind: .dm,
                    subtitle: display?.email ?? partnerID
                ))
                continue
            }

            if ch.is_mpim == true {
                // Multi-party DM — slackdump exposes these with a D-
                // prefix in the listing but the is_mpim flag is what
                // really classifies them. We don't have member names
                // in the JSON without a separate fetch, so the name
                // stays raw.
                let name = ch.name.isEmpty ? ch.id : ch.name
                channelEntities.append(SlackEntity(
                    id: ch.id,
                    name: "(group) " + name,
                    kind: .mpdm,
                    subtitle: nil
                ))
                continue
            }

            // Public / private channel. Prefix `🔒` on private so the
            // picker mirrors what users see in the Slack UI.
            let displayName = (ch.is_private == true ? "🔒 " : "#") + ch.name
            let subtitle: String? = {
                let p = ch.purpose?.value
                let t = ch.topic?.value
                if let p = p, !p.isEmpty { return p }
                if let t = t, !t.isEmpty { return t }
                return nil
            }()
            channelEntities.append(SlackEntity(
                id: ch.id,
                name: displayName,
                kind: .channel,
                subtitle: subtitle
            ))
        }

        return (channelEntities + userEntities)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Free-text filter for the type-ahead.
    func filtered(_ query: String) -> [SlackEntity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return entities }
        return entities.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || $0.id.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // MARK: - Persistence

    private struct CacheSnapshot: Codable {
        var savedAt: Date
        var entities: [SlackEntity]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func cacheURL(for workspace: String?) -> URL {
        let key = (workspace?.isEmpty == false) ? workspace! : "current"
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    private func persist(workspace: String?) {
        let snapshot = CacheSnapshot(savedAt: cacheTimestamp ?? Date(), entities: entities)
        do {
            let data = try Self.encoder.encode(snapshot)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try data.write(to: cacheURL(for: workspace), options: .atomic)
        } catch {
            NSLog("SlackSucker: channel-cache save failed — \(error.localizedDescription)")
        }
    }

    // MARK: - slackdump invocations

    /// Compose argv for `slackdump list <sub>`.
    ///
    /// Notes from the slackdump 4.3 source (verified against
    /// `slackdump help list channels` flag listing):
    ///
    /// - `-workspace` is a subcommand-level flag on `list`. It MUST
    ///   come after the `<sub>` token — putting it before `list`
    ///   errors with "flag provided but not defined: -workspace".
    /// - `-format JSON` emits a structured array on stdout. Default
    ///   behavior (without `-q`) is to print, not save, so no
    ///   `channels-<TEAM>.*` files appear in cwd. We still pin the
    ///   process cwd to `/tmp` in `capture` as a belt-and-braces.
    /// - We deliberately do NOT use `-resolve`: it injects a separate
    ///   "getting users to resolve DM names" Slack API round-trip
    ///   before the channel list emits, and the JSON already exposes
    ///   the partner's user ID in `user` for every IM row — we
    ///   resolve names locally by cross-referencing the users list.
    private static func listArgs(_ sub: String, workspaceArgs: [String]) -> [String] {
        return ["list", sub, "-format", "JSON"] + workspaceArgs
    }

    private static func runAndParseChannels(binary: String, workspaceArgs: [String]) async throws -> [RawChannel] {
        let stdout = try await capture(binary: binary,
                                       arguments: listArgs("channels", workspaceArgs: workspaceArgs))
        return try decodeJSONArray(stdout, as: RawChannel.self)
    }

    private static func runAndParseUsers(binary: String, workspaceArgs: [String]) async throws -> [RawUser] {
        let stdout = try await capture(binary: binary,
                                       arguments: listArgs("users", workspaceArgs: workspaceArgs))
        return try decodeJSONArray(stdout, as: RawUser.self)
    }

    /// Lenient JSON-array decode: strips anything before the first `[`
    /// so any stray progress / log output that slipped through to
    /// stdout doesn't break the parse. Slackdump's logger lives on
    /// stderr in `-format JSON` mode, so this rarely matters — but
    /// it's free insurance.
    nonisolated static func decodeJSONArray<T: Decodable>(_ raw: String, as type: T.Type) throws -> [T] {
        guard let firstBracket = raw.firstIndex(of: "["),
              let lastBracket  = raw.lastIndex(of: "]"),
              firstBracket < lastBracket else {
            return []
        }
        let trimmed = String(raw[firstBracket...lastBracket])
        guard let data = trimmed.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([T].self, from: data)
    }

    // MARK: - slackdump JSON shapes
    //
    // Minimal Codable mirrors of the rows slackdump emits with
    // `-format JSON`. We only decode the fields we actually use; the
    // rest of the document (image URLs, locales, team metadata, etc.)
    // is ignored by JSONDecoder, which is the behaviour we want.
    //
    // Field names match slackdump 4.3's output exactly — Slack's API
    // field naming is `snake_case`. Don't rename to camelCase without
    // adding CodingKeys.

    struct RawChannel: Codable, Equatable {
        var id: String
        var name: String           // "" for IM/MPIM rows
        var is_im: Bool?
        var is_mpim: Bool?
        var is_private: Bool?
        var is_archived: Bool?
        var is_member: Bool?
        var user: String?          // partner user ID for IM rows
        var topic: TextValue?
        var purpose: TextValue?

        struct TextValue: Codable, Equatable {
            var value: String
        }
    }

    struct RawUser: Codable, Equatable {
        var id: String
        var name: String
        var real_name: String?
        var deleted: Bool?
        var is_bot: Bool?
        var profile: Profile?

        struct Profile: Codable, Equatable {
            var display_name: String?
            var real_name: String?
            var email: String?
        }

        /// Which name to show in the picker. Slack users have several
        /// names (login `name`, `real_name`, `profile.display_name`,
        /// `profile.real_name`); we prefer the display name when set,
        /// then real_name, then login name, then ID.
        var preferredName: String {
            if let dn = profile?.display_name, !dn.isEmpty { return dn }
            if let rn = real_name, !rn.isEmpty { return rn }
            if !name.isEmpty { return name }
            return id
        }
    }

    // MARK: - Generic capture

    enum CaptureError: Error, LocalizedError {
        case nonZeroExit(status: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let status, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? ""
                return firstLine.isEmpty
                    ? "exit \(status)"
                    : "exit \(status): \(firstLine)"
            }
        }
    }

    /// Spawn `binary arguments`, capture stdout and stderr, throw on
    /// non-zero exit. cwd is pinned to the OS temp dir so any straggling
    /// side-effect files slackdump produces don't pollute the user's home
    /// or the app bundle directory.
    private static func capture(binary: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError  = err
        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw CaptureError.nonZeroExit(status: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }
}
