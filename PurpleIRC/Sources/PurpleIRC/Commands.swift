import Foundation

/// Central catalog of slash commands. Consumed by `/help` (which renders
/// the whole list in a searchable sheet) and the `/` autocomplete strip in
/// the input bar. A single source of truth means adding a new command only
/// requires updating the handler + one entry here.
enum CommandCatalog {

    enum Category: String, CaseIterable, Identifiable {
        case connection = "Connection"
        case channels   = "Channels"
        case messages   = "Messages"
        case identity   = "Identity"
        case moderation = "Moderation"
        case user       = "User lookup"
        case bot        = "Bot"
        case app        = "App"
        var id: String { rawValue }
    }

    struct Entry: Identifiable, Hashable {
        let id: String          // the command name, lowercased, no leading /
        let args: String        // e.g. "<nick> [reason]"
        let summary: String
        let category: Category
        /// Alternate names that resolve to the same command (for search + /help).
        let aliases: [String]
    }

    static let all: [Entry] = [
        // Connection
        .init(id: "connect",    args: "",               summary: "Connect the active server profile.",                         category: .connection, aliases: []),
        .init(id: "disconnect", args: "[reason]",       summary: "Disconnect this network (the app keeps running).",           category: .connection, aliases: []),
        .init(id: "quit",       args: "[reason]",       summary: "Close PurpleIRC (QUITs every network first).",               category: .app,        aliases: ["exit"]),

        // Channels
        .init(id: "join",       args: "<channel>",      summary: "Join a channel.",                                             category: .channels,   aliases: ["j"]),
        .init(id: "part",       args: "[channel] [reason]", summary: "Leave the current or named channel.",                    category: .channels,   aliases: []),
        .init(id: "topic",      args: "[new topic]",    summary: "Request or set the current channel topic.",                  category: .channels,   aliases: []),
        .init(id: "names",      args: "",               summary: "Re-fetch the current channel's user list.",                  category: .channels,   aliases: []),
        .init(id: "mode",       args: "[target] [modes]", summary: "Query or change channel/user modes.",                      category: .channels,   aliases: []),
        .init(id: "list",       args: "[filter|full]",  summary: "Open the channel directory. /list full forces a refresh.",   category: .channels,   aliases: []),
        .init(id: "close",      args: "",               summary: "Close the current buffer (part if channel).",                category: .channels,   aliases: []),

        // Messages
        .init(id: "msg",        args: "<target> <text>", summary: "Send a private message (opens a query buffer).",            category: .messages,   aliases: []),
        .init(id: "query",      args: "<nick>",         summary: "Open a private message buffer with a nick.",                 category: .messages,   aliases: []),
        .init(id: "me",         args: "<action>",       summary: "Send a /me-style action to the current buffer.",             category: .messages,   aliases: []),
        .init(id: "notice",     args: "<target> <text>", summary: "Send an IRC NOTICE (not a PRIVMSG).",                       category: .messages,   aliases: []),
        .init(id: "ctcp",       args: "<target> <cmd>", summary: "Send a CTCP request (e.g. VERSION, PING).",                  category: .messages,   aliases: []),
        .init(id: "raw",        args: "<line>",         summary: "Send an unmodified IRC line to the server.",                 category: .messages,   aliases: ["quote"]),

        // Identity
        .init(id: "nick",       args: "<new nick>",     summary: "Change your nickname on this network.",                      category: .identity,   aliases: []),
        .init(id: "away",       args: "[reason]",       summary: "Mark yourself away with an optional reason.",                category: .identity,   aliases: []),
        .init(id: "back",       args: "",               summary: "Clear the away status.",                                     category: .identity,   aliases: []),
        .init(id: "identity",   args: "[name|custom]",  summary: "Show or switch the linked identity on this connection.",     category: .identity,   aliases: []),

        // Moderation
        .init(id: "op",         args: "<nick>",         summary: "Grant channel operator (+o).",                               category: .moderation, aliases: []),
        .init(id: "deop",       args: "<nick>",         summary: "Remove channel operator (-o).",                              category: .moderation, aliases: []),
        .init(id: "voice",      args: "<nick>",         summary: "Grant voice (+v).",                                          category: .moderation, aliases: []),
        .init(id: "devoice",    args: "<nick>",         summary: "Remove voice (-v).",                                         category: .moderation, aliases: []),
        .init(id: "kick",       args: "<nick> [reason]", summary: "Kick a user from the current channel.",                     category: .moderation, aliases: []),
        .init(id: "ban",        args: "<mask>",         summary: "Ban a mask from the current channel.",                       category: .moderation, aliases: []),
        .init(id: "unban",      args: "<mask>",         summary: "Remove a ban.",                                              category: .moderation, aliases: []),
        .init(id: "ignore",     args: "[mask]",         summary: "Ignore a nick/hostmask. No arg lists current ignores.",      category: .moderation, aliases: []),
        .init(id: "unignore",   args: "<mask>",         summary: "Stop ignoring a mask.",                                      category: .moderation, aliases: []),

        // User lookup
        .init(id: "whois",      args: "<nick>",         summary: "Look up a user on this network.",                            category: .user,       aliases: []),
        .init(id: "whowas",     args: "<nick>",         summary: "Look up a nick's most recent record after they've quit.",    category: .user,       aliases: []),
        .init(id: "seen",       args: "[nick]",         summary: "Inline /seen <nick>, or open the seen log sheet with no arg.", category: .user,     aliases: []),

        // Bot
        .init(id: "reloadbots", args: "",               summary: "Reload all PurpleBot JavaScript scripts.",                    category: .bot,        aliases: ["reloadscripts"]),

        // App
        .init(id: "help",       args: "[command]",      summary: "Open help. With an argument, jump to that command.",          category: .app,        aliases: []),
    ]

    /// Case-insensitive prefix match on the command name. Returns entries
    /// sorted so exact-prefix matches come before alias matches. `query` is
    /// without the leading slash.
    static func matches(prefix query: String) -> [Entry] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { e in
            e.id.hasPrefix(q) || e.aliases.contains(where: { $0.hasPrefix(q) })
        }.sorted { a, b in
            let aExact = a.id.hasPrefix(q) ? 0 : 1
            let bExact = b.id.hasPrefix(q) ? 0 : 1
            if aExact != bExact { return aExact < bExact }
            return a.id < b.id
        }
    }

    /// Loose search used by /help's sheet — matches id, alias, or summary.
    static func search(_ query: String) -> [Entry] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { e in
            e.id.contains(q)
                || e.aliases.contains(where: { $0.contains(q) })
                || e.summary.lowercased().contains(q)
        }
    }
}
