import Foundation
import Combine

/// Native bot functionality that runs alongside the JavaScriptCore `BotHost`.
/// Subscribes to ChatModel's merged event stream and:
///   - records join/part/quit/msg/nick activity into `SeenStore` for `/seen`
///   - evaluates user-configured `TriggerRule`s and sends auto-replies
///
/// Anti-loop: triggers never fire on the user's own nick. Every response is
/// routed to the *originating* connection (not just the active one), so users
/// can run the same trigger set across multiple networks safely.
@MainActor
final class BotEngine {
    private weak var model: ChatModel?
    let seenStore: SeenStore
    private var cancellables: Set<AnyCancellable> = []

    /// Per-rule compiled regex cache. Invalidate via `clearRegexCache()` after
    /// the user edits rules.
    private var triggerRegexCache: [UUID: NSRegularExpression] = [:]

    init(seenStore: SeenStore) {
        self.seenStore = seenStore
    }

    /// Called once during ChatModel.init after `self` is fully formed.
    func attach(to model: ChatModel) {
        self.model = model
        subscribe()
    }

    /// Drop cached compiled regexes; recompile happens on next evaluation.
    func clearRegexCache() {
        triggerRegexCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Event subscription

    private func subscribe() {
        guard let model else { return }
        model.events
            .sink { [weak self] tuple in
                Task { @MainActor in
                    self?.handle(connectionID: tuple.0, event: tuple.1)
                }
            }
            .store(in: &cancellables)
    }

    private func handle(connectionID: UUID, event: IRCConnectionEvent) {
        guard let model, let conn = model.connections.first(where: { $0.id == connectionID }) else { return }
        let settings = model.settings.settings
        switch event {
        case .privmsg(let from, let target, let text, _, _):
            if settings.seenTrackingEnabled, !isSelf(nick: from, on: conn) {
                record(on: conn, nick: from, kind: "msg",
                       channel: target.hasPrefix("#") ? target : nil,
                       detail: truncated(text))
            }
            evaluateTriggers(conn: conn, from: from, target: target, text: text, settings: settings)
        case .join(let nick, let channel, let isSelf):
            if settings.seenTrackingEnabled, !isSelf {
                record(on: conn, nick: nick, kind: "join", channel: channel, detail: nil)
            }
        case .part(let nick, let channel, let reason, let isSelf):
            if settings.seenTrackingEnabled, !isSelf {
                record(on: conn, nick: nick, kind: "part", channel: channel, detail: reason)
            }
        case .quit(let nick, let reason):
            if settings.seenTrackingEnabled, nick.lowercased() != conn.nick.lowercased() {
                record(on: conn, nick: nick, kind: "quit", channel: nil, detail: reason)
            }
        case .nickChanged(let old, let new, let isSelf):
            if settings.seenTrackingEnabled, !isSelf {
                // Both old and new nicks share the same user@host on a
                // rename, so a single lookup is enough.
                let userHost = conn.userHost(for: new) ?? conn.userHost(for: old)
                seenStore.recordNickChange(
                    networkID: conn.id,
                    networkSlug: SeenStore.slug(for: conn.displayName),
                    oldNick: old,
                    newNick: new,
                    userHost: userHost
                )
            }
        default:
            break
        }
    }

    private func record(on conn: IRCConnection, nick: String, kind: String,
                        channel: String?, detail: String?) {
        seenStore.record(
            networkID: conn.id,
            networkSlug: SeenStore.slug(for: conn.displayName),
            nick: nick,
            kind: kind,
            channel: channel,
            detail: detail,
            // Pull the freshest known user@host from the connection so
            // each sighting can later be cross-referenced (host changes,
            // shared hosts across nicks, etc.).
            userHost: conn.userHost(for: nick)
        )
    }

    private func isSelf(nick: String, on conn: IRCConnection) -> Bool {
        nick.lowercased() == conn.nick.lowercased()
    }

    private func truncated(_ s: String) -> String {
        let stripped = IRCFormatter.stripCodes(s)
        if stripped.count <= 200 { return stripped }
        return String(stripped.prefix(200)) + "…"
    }

    // MARK: - Triggers

    private func evaluateTriggers(conn: IRCConnection,
                                  from: String,
                                  target: String,
                                  text: String,
                                  settings: AppSettings) {
        guard !isSelf(nick: from, on: conn) else { return }

        let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
        let replyTarget = isChannel ? target : from
        let stripped = IRCFormatter.stripCodes(text)

        for rule in settings.triggerRules {
            guard rule.enabled, !rule.pattern.isEmpty else { continue }
            if !rule.networks.isEmpty, !rule.networks.contains(conn.profile.id) { continue }
            switch rule.scope {
            case .channel: if !isChannel { continue }
            case .query:   if isChannel { continue }
            case .both:    break
            }
            guard let hit = firstMatch(rule: rule, in: stripped) else { continue }
            let reply = Self.expandResponse(rule.response,
                                            match: hit.match,
                                            groups: hit.groups,
                                            nick: from,
                                            channel: isChannel ? target : from)
            guard !reply.isEmpty else { continue }
            conn.sendRaw("PRIVMSG \(replyTarget) :\(reply)")
        }
    }

    // MARK: - Public API used by /seen command

    /// Look up a seen entry on the given connection. Exposed so
    /// ChatModel's `/seen` intercept can render the inline info line.
    func seen(on conn: IRCConnection, nick: String) -> SeenEntry? {
        seenStore.lookup(
            networkID: conn.id,
            networkSlug: SeenStore.slug(for: conn.displayName),
            nick: nick
        )
    }

    /// Human-friendly summary of a seen entry. Used by /seen and by the
    /// Bot setup test button.
    nonisolated static func describe(_ entry: SeenEntry, queriedNick: String) -> String {
        let when = Self.formatRelative(entry.timestamp)
        let target = entry.nick
        // user@host suffix appears at the end of the line so /seen output
        // stays scannable while still surfacing the host info.
        let host = entry.lastUserHost.map { " [\($0)]" } ?? ""
        let historyTail: String = {
            let n = max(0, entry.history.count - 1)
            guard n > 0 else { return "" }
            return " — \(n) more sighting\(n == 1 ? "" : "s") on file"
        }()
        switch entry.kind {
        case "msg":
            let where_ = entry.channel.map { " in \($0)" } ?? ""
            let sample = entry.detail.map { ", saying \"\($0)\"" } ?? ""
            return "\(target) was last seen \(when)\(where_)\(sample)\(host)\(historyTail)"
        case "join":
            let where_ = entry.channel.map { " joining \($0)" } ?? ""
            return "\(target) was last seen \(when)\(where_)\(host)\(historyTail)"
        case "part":
            let where_ = entry.channel.map { " leaving \($0)" } ?? ""
            let reason = entry.detail.map { " (\($0))" } ?? ""
            return "\(target) was last seen \(when)\(where_)\(reason)\(host)\(historyTail)"
        case "quit":
            let reason = entry.detail.map { " (\($0))" } ?? ""
            return "\(target) was last seen \(when), quitting\(reason)\(host)\(historyTail)"
        case "nick":
            if let renamed = entry.renamedTo {
                return "\(target) changed nick to \(renamed) \(when)\(host). Try /seen \(renamed)."
            }
            if let was = entry.detail {
                return "\(target) (\(was)) was last seen \(when)\(host)\(historyTail)"
            }
            return "\(target) changed nick \(when)\(host)"
        default:
            return "\(target) was last seen \(when)\(host)\(historyTail)"
        }
    }

    nonisolated private static func formatRelative(_ when: Date) -> String {
        let delta = Date().timeIntervalSince(when)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let m = Int(delta / 60)
            return "\(m)m ago"
        }
        if delta < 86_400 {
            let h = Int(delta / 3600)
            return "\(h)h ago"
        }
        let d = Int(delta / 86_400)
        return "\(d)d ago"
    }

    // MARK: - Regex / expansion (static so tests can drive them directly)

    private struct MatchResult {
        let match: String       // the whole match text
        let groups: [String]    // capture groups 1..N; index 0 is the whole match
    }

    private func firstMatch(rule: TriggerRule, in haystack: String) -> MatchResult? {
        guard let regex = regex(for: rule) else { return nil }
        let full = NSRange(haystack.startIndex..., in: haystack)
        guard let m = regex.firstMatch(in: haystack, options: [], range: full) else { return nil }
        let whole = (Range(m.range, in: haystack)).map { String(haystack[$0]) } ?? ""
        var groups: [String] = [whole]
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound {
                groups.append("")
            } else if let swiftR = Range(r, in: haystack) {
                groups.append(String(haystack[swiftR]))
            } else {
                groups.append("")
            }
        }
        return MatchResult(match: whole, groups: groups)
    }

    private func regex(for rule: TriggerRule) -> NSRegularExpression? {
        if let cached = triggerRegexCache[rule.id] { return cached }
        var options: NSRegularExpression.Options = []
        if !rule.caseSensitive { options.insert(.caseInsensitive) }
        let pattern: String
        if rule.isRegex {
            pattern = rule.pattern
        } else {
            // Literal mode: escape metacharacters and wrap in word boundaries
            // so "!rules" doesn't fire on "foo!rulesbar". IRC-nick chars count
            // as word chars so `!rules` + `!rules2` both match cleanly.
            let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
            pattern = "(?<![A-Za-z0-9_\\-\\[\\]{}|^\\\\])\(escaped)(?![A-Za-z0-9_\\-\\[\\]{}|^\\\\])"
        }
        do {
            let re = try NSRegularExpression(pattern: pattern, options: options)
            triggerRegexCache[rule.id] = re
            return re
        } catch {
            return nil
        }
    }

    /// Replace `$nick`, `$channel`, `$match`, `$1..$9` placeholders. Unknown
    /// placeholders are left intact so the user sees what they typed.
    nonisolated static func expandResponse(_ template: String,
                               match: String,
                               groups: [String],
                               nick: String,
                               channel: String) -> String {
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            if c != "$" {
                out.append(c)
                i = template.index(after: i)
                continue
            }
            let nextIdx = template.index(after: i)
            guard nextIdx < template.endIndex else {
                out.append(c); i = nextIdx; continue
            }
            let next = template[nextIdx]
            // $1..$9 — capture group
            if next.isNumber, let digit = Int(String(next)), digit >= 1, digit <= 9 {
                if digit < groups.count {
                    out.append(groups[digit])
                }
                i = template.index(after: nextIdx)
                continue
            }
            // Longest-match keyword expansion
            let remainder = template[nextIdx...]
            if remainder.hasPrefix("channel") {
                out.append(channel)
                i = template.index(nextIdx, offsetBy: "channel".count)
            } else if remainder.hasPrefix("match") {
                out.append(match)
                i = template.index(nextIdx, offsetBy: "match".count)
            } else if remainder.hasPrefix("nick") {
                out.append(nick)
                i = template.index(nextIdx, offsetBy: "nick".count)
            } else {
                out.append(c)
                i = nextIdx
            }
        }
        return out
    }
}
