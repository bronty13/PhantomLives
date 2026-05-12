import Foundation

// Person-model helpers on `AddressEntry`.
//
// The model was extended in 1.0.242 to let one contact span multiple
// `LinkedNick` bindings (a (network slug, nick) pair plus a `source`
// provenance tag). This file is the home for the cross-network read
// helpers built on top — match-by-(slug,nick), sighting fold across
// every linked nick, hostmask history across every linked nick, and
// the on-demand auto-link suggestion engine.
//
// Everything in this file is pure: no published state, no actor hops,
// no I/O of its own. Callers pass in whatever live connections /
// `SeenStore` they want folded.

extension AddressEntry {

    /// True iff this contact answers to the given (network slug, nick).
    /// Honors the `""` any-network sentinel that pre-1.0.242 entries
    /// migrate to, AND case-insensitive nick comparison. This is the
    /// helper every call site that used to do
    /// `entry.nick.caseInsensitiveCompare(target) == .orderedSame`
    /// should funnel through — otherwise the legacy any-network
    /// migration silently stops matching on the network-specific paths.
    func matches(networkSlug: String, nick: String) -> Bool {
        let targetLower = nick.lowercased()
        for ln in linkedNicks {
            if ln.nick.lowercased() != targetLower { continue }
            if ln.networkSlug.isEmpty { return true }       // any-network sentinel
            if ln.networkSlug == networkSlug { return true }
        }
        return false
    }

    /// "Does any of this contact's linked nicks match this string?"
    /// — for call sites that don't have a network slug handy (e.g.
    /// `ContactAvatarByNick` which renders just from a nick string).
    /// More permissive than `matches(networkSlug:nick:)`: ignores
    /// network scoping entirely. Use the network-scoped variant when
    /// you do have a slug (sidebar contact rows, BufferView nick
    /// menus); use this one only when you genuinely don't.
    func matchesAnyNetwork(nick: String) -> Bool {
        let target = nick.lowercased()
        return linkedNicks.contains { $0.nick.lowercased() == target }
    }

    /// Convenience: returns every linked nick lowercased + deduped.
    /// Used by the "filter recent watch hits to this contact" view in
    /// the workspace.
    func allLinkedNicksLowercased() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for ln in linkedNicks {
            let k = ln.nick.lowercased()
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            out.append(k)
        }
        return out
    }

    /// Fold every sighting from every linked nick on every connected
    /// network into one timeline, newest first. Each result tuple
    /// carries the network display name (for rendering "in #swift on
    /// Libera, 3h ago") plus the raw `SeenSighting`.
    ///
    /// Empty-slug bindings (the legacy "any network" sentinel) probe
    /// every connection. Bindings with a specific slug only probe the
    /// matching connection.
    @MainActor
    func allSightings(across connections: [IRCConnection],
                      store: SeenStore) -> [ContactSighting] {
        var out: [ContactSighting] = []
        for ln in linkedNicks {
            for conn in connections {
                let connSlug = SeenStore.slug(for: conn.displayName)
                if !ln.networkSlug.isEmpty, ln.networkSlug != connSlug { continue }
                guard let entry = store.lookup(networkID: conn.id,
                                                networkSlug: connSlug,
                                                nick: ln.nick) else { continue }
                for sight in entry.history {
                    out.append(ContactSighting(
                        sighting: sight,
                        networkID: conn.id,
                        networkName: conn.displayName,
                        nick: entry.nick))
                }
            }
        }
        out.sort { $0.sighting.timestamp > $1.sighting.timestamp }
        return out
    }

    /// Distinct `user@host` strings ever seen for this contact, with
    /// first/last sighting timestamps. Powers the hostmask-history
    /// section of the contact card — useful for spotting when a
    /// familiar nick reconnects from a new ISP or for noticing two
    /// known nicks sharing a host.
    @MainActor
    func allCurrentHostmasks(across connections: [IRCConnection],
                              store: SeenStore) -> [ContactHostmask] {
        // Build the timeline once, then collapse by host.
        var byHost: [String: ContactHostmask] = [:]
        for cs in allSightings(across: connections, store: store) {
            guard let host = cs.sighting.userHost, !host.isEmpty else { continue }
            if var existing = byHost[host] {
                if cs.sighting.timestamp < existing.firstSeen {
                    existing.firstSeen = cs.sighting.timestamp
                }
                if cs.sighting.timestamp > existing.lastSeen {
                    existing.lastSeen = cs.sighting.timestamp
                }
                byHost[host] = existing
            } else {
                byHost[host] = ContactHostmask(
                    host: host,
                    firstSeen: cs.sighting.timestamp,
                    lastSeen: cs.sighting.timestamp)
            }
        }
        return byHost.values.sorted { $0.lastSeen > $1.lastSeen }
    }
}

/// One row in the merged contact-activity timeline. Carries the
/// originating network so the renderer can show "in #swift on Libera".
struct ContactSighting: Hashable, Identifiable {
    var id: String {
        "\(networkID.uuidString)|\(nick.lowercased())|\(Int(sighting.timestamp.timeIntervalSince1970))|\(sighting.kind)|\(sighting.channel ?? "")"
    }
    let sighting: SeenSighting
    let networkID: UUID
    let networkName: String
    /// The nick the sighting was recorded under. May differ in case
    /// from `AddressEntry.nick` (the canonical one) or even differ in
    /// spelling for a linked alt (e.g. `alice_`).
    let nick: String
}

/// Distinct hostmask plus first/last-seen window. Sorted newest-last
/// in the address-book workspace's Hostmask History section.
struct ContactHostmask: Hashable, Identifiable {
    var id: String { host }
    let host: String
    var firstSeen: Date
    var lastSeen: Date
}

/// One suggested link the user can accept to merge another (network,
/// nick) under an existing contact. Powered by host-overlap and
/// IRCv3 `account-tag` matches — never auto-applied; the workspace
/// surfaces these as a list the user explicitly confirms.
struct ContactLinkSuggestion: Hashable, Identifiable {
    var id: String { "\(addressID.uuidString)|\(networkSlug)|\(nick.lowercased())|\(reason.rawValue)" }
    let addressID: UUID
    let networkSlug: String
    let nick: String
    let reason: Reason

    enum Reason: String, Hashable {
        case sharedHostmask
        case sharedServicesAccount
    }

    /// `LinkedNick.Source` value to stamp if the user accepts.
    var asLinkedNickSource: LinkedNick.Source {
        switch reason {
        case .sharedHostmask:        return .hostmask
        case .sharedServicesAccount: return .accountTag
        }
    }
}

/// Compute the suggested link list for every contact, on demand.
///
/// Two heuristics:
///   • **Shared hostmask** — a `SeenEntry.lastUserHost` (or any entry
///     in the rolling history) seen on Network B matches a host seen
///     on Network A under a nick that's already linked to a contact.
///   • **Shared services account** — IRCv3 `account-tag` exposes the
///     services account a user is logged into; two nicks reporting the
///     same account on different networks are almost certainly the
///     same person.
///
/// This is a read-only helper. The workspace surfaces the suggestions
/// behind a "Suggest links" button; nothing is mutated until the user
/// explicitly accepts.
@MainActor
enum ContactLinker {
    static func suggestLinks(in addressBook: [AddressEntry],
                              seen: SeenStore,
                              connections: [IRCConnection]) -> [ContactLinkSuggestion] {
        // Index 1: every (slug, lower-nick) pair already linked,
        // mapped to its address-entry id, so we don't re-suggest what's
        // already linked.
        var linkedIndex: [String: UUID] = [:]
        for entry in addressBook {
            for ln in entry.linkedNicks {
                let k = "\(ln.networkSlug)|\(ln.nick.lowercased())"
                linkedIndex[k] = entry.id
            }
        }

        var out: [ContactLinkSuggestion] = []
        for entry in addressBook {
            // Gather the known account tags + hostmasks for this contact
            // across every linked-nick / connected-network combination.
            var knownAccounts: Set<String> = []
            var knownHosts: Set<String> = []
            for ln in entry.linkedNicks {
                for conn in connections {
                    let connSlug = SeenStore.slug(for: conn.displayName)
                    if !ln.networkSlug.isEmpty, ln.networkSlug != connSlug { continue }
                    if let acct = conn.accountByNick[ln.nick.lowercased()], !acct.isEmpty {
                        knownAccounts.insert(acct)
                    }
                    if let host = conn.userHost(for: ln.nick), !host.isEmpty {
                        knownHosts.insert(host)
                    }
                    if let existing = seen.lookup(networkID: conn.id,
                                                   networkSlug: connSlug,
                                                   nick: ln.nick) {
                        if let lh = existing.lastUserHost, !lh.isEmpty {
                            knownHosts.insert(lh)
                        }
                        for sight in existing.history {
                            if let uh = sight.userHost, !uh.isEmpty {
                                knownHosts.insert(uh)
                            }
                        }
                    }
                }
            }
            guard !knownAccounts.isEmpty || !knownHosts.isEmpty else { continue }

            // Scan every connected network's seen entries; flag ones
            // that share an account or host with this contact AND
            // aren't already linked to anyone (or are linked to a
            // different contact — we don't suggest stealing).
            for conn in connections {
                let connSlug = SeenStore.slug(for: conn.displayName)
                for candidate in seen.entries(networkID: conn.id,
                                                networkSlug: connSlug) {
                    let candidateKey = "\(connSlug)|\(candidate.nick.lowercased())"
                    if linkedIndex[candidateKey] == entry.id { continue }  // already linked here
                    if linkedIndex[candidateKey] != nil { continue }       // linked to someone else
                    let anyKey = "|\(candidate.nick.lowercased())"          // legacy any-net binding
                    if linkedIndex[anyKey] != nil { continue }

                    let candidateAccount = conn.accountByNick[candidate.nick.lowercased()]
                    let candidateHosts = Set([candidate.lastUserHost].compactMap { $0 }
                                              + candidate.history.compactMap { $0.userHost })

                    if let acct = candidateAccount, knownAccounts.contains(acct) {
                        out.append(ContactLinkSuggestion(
                            addressID: entry.id, networkSlug: connSlug,
                            nick: candidate.nick, reason: .sharedServicesAccount))
                        continue
                    }
                    if !candidateHosts.isDisjoint(with: knownHosts) {
                        out.append(ContactLinkSuggestion(
                            addressID: entry.id, networkSlug: connSlug,
                            nick: candidate.nick, reason: .sharedHostmask))
                    }
                }
            }
        }
        return out
    }
}
