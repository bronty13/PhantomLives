import Foundation

/// Central catalog of slash commands. Consumed by `/help` (which renders
/// the whole list in a searchable sheet) and the `/` autocomplete strip in
/// the input bar. A single source of truth means adding a new command only
/// requires updating the handler + one entry here.
enum CommandCatalog {

    enum Category: String, CaseIterable, Identifiable {
        case connection  = "Connection"
        case channels    = "Channels"
        case messages    = "Messages"
        case identity    = "Identity"
        case moderation  = "Moderation"
        case user        = "User lookup"
        case bot         = "Bot"
        case appearance  = "Appearance"
        case window      = "Window & buffer"
        case server      = "Server info"
        case dcc         = "DCC"
        case logs        = "Logs"
        case automation  = "Automation"
        case dangerous   = "Dangerous"
        case app         = "App"
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
        .init(id: "connect",    args: "",                  summary: "Connect the active server profile.",                                category: .connection, aliases: []),
        .init(id: "disconnect", args: "[reason]",          summary: "Disconnect this network (the app keeps running).",                  category: .connection, aliases: []),
        .init(id: "reconnect",  args: "",                  summary: "Disconnect and reconnect this network without waiting on backoff.", category: .connection, aliases: []),
        .init(id: "quit",       args: "[reason]",          summary: "Close PurpleIRC (QUITs every network first).",                      category: .app,        aliases: ["exit"]),

        // Channels
        .init(id: "join",       args: "<channel>",         summary: "Join a channel.",                                                    category: .channels,   aliases: ["j"]),
        .init(id: "part",       args: "[channel] [reason]", summary: "Leave the current or named channel.",                               category: .channels,   aliases: []),
        .init(id: "rejoin",     args: "[reason]",          summary: "PART and JOIN the current channel — refreshes membership / modes.",  category: .channels,   aliases: ["cycle"]),
        .init(id: "topic",      args: "[new topic]",       summary: "Request or set the current channel topic.",                          category: .channels,   aliases: []),
        .init(id: "names",      args: "",                  summary: "Re-fetch the current channel's user list.",                          category: .channels,   aliases: []),
        .init(id: "mode",       args: "[target] [modes]",  summary: "Query or change channel/user modes.",                                category: .channels,   aliases: []),
        .init(id: "list",       args: "[filter|full]",     summary: "Open the channel directory. /list full forces a refresh.",           category: .channels,   aliases: []),
        .init(id: "close",      args: "",                  summary: "Close the current buffer (part if channel).",                        category: .channels,   aliases: []),
        .init(id: "invite",     args: "<nick> [#channel]", summary: "INVITE a nick to a channel (defaults to current).",                  category: .channels,   aliases: []),
        .init(id: "knock",      args: "<#channel> [reason]", summary: "KNOCK on an invite-only channel (server-dependent).",              category: .channels,   aliases: []),

        // Messages
        .init(id: "msg",        args: "<target> <text>",   summary: "Send a private message (opens a query buffer).",                     category: .messages,   aliases: []),
        .init(id: "query",      args: "<nick>",            summary: "Open a private message buffer with a nick.",                         category: .messages,   aliases: []),
        .init(id: "me",         args: "<action>",          summary: "Send a /me-style action to the current buffer.",                     category: .messages,   aliases: []),
        .init(id: "notice",     args: "<target> <text>",   summary: "Send an IRC NOTICE (not a PRIVMSG).",                                category: .messages,   aliases: []),
        .init(id: "ctcp",       args: "<target> <cmd>",    summary: "Send a CTCP request (e.g. VERSION, PING).",                          category: .messages,   aliases: []),
        .init(id: "raw",        args: "<line>",            summary: "Send an unmodified IRC line to the server.",                         category: .messages,   aliases: ["quote"]),

        // Identity
        .init(id: "nick",       args: "<new nick>",        summary: "Change your nickname on this network.",                              category: .identity,   aliases: []),
        .init(id: "away",       args: "[reason]",          summary: "Mark yourself away with an optional reason.",                        category: .identity,   aliases: []),
        .init(id: "back",       args: "",                  summary: "Clear the away status.",                                             category: .identity,   aliases: []),
        .init(id: "identity",   args: "[name|custom]",     summary: "Show or switch the linked identity on this connection.",             category: .identity,   aliases: []),

        // Moderation
        .init(id: "op",         args: "<nick>",            summary: "Grant channel operator (+o).",                                       category: .moderation, aliases: []),
        .init(id: "deop",       args: "<nick>",            summary: "Remove channel operator (-o).",                                      category: .moderation, aliases: []),
        .init(id: "voice",      args: "<nick>",            summary: "Grant voice (+v).",                                                  category: .moderation, aliases: []),
        .init(id: "devoice",    args: "<nick>",            summary: "Remove voice (-v).",                                                 category: .moderation, aliases: []),
        .init(id: "kick",       args: "<nick> [reason]",   summary: "Kick a user from the current channel.",                              category: .moderation, aliases: []),
        .init(id: "ban",        args: "<mask>",            summary: "Ban a mask from the current channel.",                               category: .moderation, aliases: []),
        .init(id: "unban",      args: "<mask>",            summary: "Remove a ban.",                                                      category: .moderation, aliases: []),
        .init(id: "ignore",     args: "[mask]",            summary: "Ignore a nick/hostmask. No arg lists current ignores.",              category: .moderation, aliases: []),
        .init(id: "unignore",   args: "<mask>",            summary: "Stop ignoring a mask.",                                              category: .moderation, aliases: []),
        .init(id: "silence",    args: "[+/-mask]",         summary: "Server-side ignore (DALnet/EFnet variants). Empty = list.",          category: .moderation, aliases: []),
        .init(id: "unsilence",  args: "<mask>",            summary: "Remove a server-side SILENCE entry.",                                category: .moderation, aliases: []),

        // User lookup
        .init(id: "whois",      args: "<nick>",            summary: "Look up a user on this network.",                                    category: .user,       aliases: []),
        .init(id: "whowas",     args: "<nick>",            summary: "Look up a nick's most recent record after they've quit.",            category: .user,       aliases: []),
        .init(id: "seen",       args: "[nick]",            summary: "Inline /seen <nick>, or open the seen log sheet with no arg.",       category: .user,       aliases: []),
        .init(id: "watch",      args: "<nick>",            summary: "Add a nick to the address-book watch list.",                         category: .user,       aliases: []),
        .init(id: "unwatch",    args: "<nick>",            summary: "Remove a nick from the watch list.",                                 category: .user,       aliases: []),

        // Server info
        .init(id: "motd",       args: "",                  summary: "Request the server's Message of the Day.",                           category: .server,     aliases: []),
        .init(id: "lusers",     args: "",                  summary: "Request user / server count for this network.",                      category: .server,     aliases: []),
        .init(id: "admin",      args: "",                  summary: "Request the server's administrative contact info.",                  category: .server,     aliases: []),
        .init(id: "info",       args: "",                  summary: "Request the server's INFO block.",                                   category: .server,     aliases: []),
        .init(id: "version",    args: "",                  summary: "Request the server's software version.",                             category: .server,     aliases: []),

        // DCC
        .init(id: "dcc",        args: "send|chat|list <args>", summary: "DCC offers and inbound list. /dcc send <nick> [path], /dcc chat <nick>.", category: .dcc, aliases: []),

        // Window & buffer
        .init(id: "clear",      args: "",                  summary: "Clear the current buffer's scrollback (UI only; channel stays joined).", category: .window, aliases: ["cls"]),
        .init(id: "find",       args: "[query]",           summary: "Open the find bar, pre-filled with [query].",                        category: .window,     aliases: ["search"]),
        .init(id: "markread",   args: "",                  summary: "Reset unread badges across every buffer on every network.",          category: .window,     aliases: ["markallread"]),
        .init(id: "next",       args: "",                  summary: "Cycle to the next buffer on this network.",                          category: .window,     aliases: ["nextbuffer"]),
        .init(id: "prev",       args: "",                  summary: "Cycle to the previous buffer on this network.",                      category: .window,     aliases: ["previous", "prevbuffer"]),
        .init(id: "goto",       args: "<buffer-name>",     summary: "Jump to a buffer on this network (fuzzy match).",                    category: .window,     aliases: ["switch"]),
        .init(id: "network",    args: "[name]",            summary: "Switch active network, or list connected ones.",                     category: .window,     aliases: []),

        // Appearance
        .init(id: "theme",      args: "[name]",            summary: "List themes or switch to one by id.",                                category: .appearance, aliases: []),
        .init(id: "font",       args: "+|-|reset|<pt>|family <name>", summary: "Adjust chat font size or family.",                        category: .appearance, aliases: []),
        .init(id: "density",    args: "compact|cozy|comfortable", summary: "Switch chat-row vertical density.",                           category: .appearance, aliases: []),
        .init(id: "zoom",       args: "+|-|reset|<0.5–2.0>", summary: "Whole-buffer text zoom multiplier.",                                category: .appearance, aliases: []),
        .init(id: "timestamp",  args: "on|off|<pattern>",  summary: "Show, hide, or set the chat-line timestamp pattern.",                category: .appearance, aliases: ["ts"]),

        // Logs / diagnostic
        .init(id: "log",        args: "",                  summary: "Open the diagnostic app log viewer.",                                category: .logs,       aliases: ["applog", "debuglog"]),
        .init(id: "logs",       args: "",                  summary: "Open the per-buffer chat log viewer.",                               category: .logs,       aliases: ["viewlogs", "chatlog", "chatlogs"]),
        .init(id: "export",     args: "buffer|all",        summary: "Export the current buffer or all buffers as plaintext under ~/Downloads/PurpleIRC export/.", category: .logs, aliases: []),

        // Bot / automation
        .init(id: "reloadbots", args: "",                  summary: "Reload all PurpleBot JavaScript scripts.",                           category: .bot,        aliases: ["reloadscripts"]),
        .init(id: "assist",     args: "",                  summary: "Toggle the local-LLM assistant suggestion strip on the active query.", category: .bot,     aliases: ["ai", "bot"]),
        .init(id: "alias",      args: "[name [expansion]]", summary: "Define, list, or remove user aliases. /alias -name removes.",       category: .automation, aliases: []),
        .init(id: "repeat",     args: "<count 1-20> <command>", summary: "Run a command N times with a 250 ms inter-fire delay.",         category: .automation, aliases: []),
        .init(id: "timer",      args: "<seconds 1-3600> <command>", summary: "Fire a command after a one-shot delay.",                    category: .automation, aliases: []),
        .init(id: "summary",    args: "[N]",               summary: "Local-LLM summary of the last N lines (requires assistant).",        category: .automation, aliases: []),
        .init(id: "translate",  args: "<language>",        summary: "Translate the next inbound message (requires assistant).",           category: .automation, aliases: []),

        // Dangerous
        .init(id: "lock",       args: "",                  summary: "Lock the keystore now — requires re-entering the passphrase.",       category: .dangerous,  aliases: []),
        .init(id: "backup",     args: "",                  summary: "Open the backup sheet under Setup → Behavior.",                      category: .dangerous,  aliases: []),
        .init(id: "nuke",       args: "",                  summary: "DESTRUCTIVE: wipe every file and Keychain item PurpleIRC owns. Two-step confirm.", category: .dangerous, aliases: []),

        // App
        .init(id: "help",       args: "[command]",         summary: "Open help. With an argument, jump to that command.",                 category: .app,        aliases: []),
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
