import Foundation

/// A launchd agent as read from its `~/Library/LaunchAgents/<label>.plist`.
/// Pure value type — parsing and the `StartInterval` mutation are side-effect-free
/// and unit-testable; the controller owns the actual file I/O and `launchctl` calls.
struct AgentDescriptor: Equatable {
    var label: String
    var programArguments: [String]
    var startInterval: Int?
    var stdoutPath: String?
    var stderrPath: String?
    var runAtLoad: Bool
    var environment: [String: String]

    /// Best-effort "the script this agent runs" — the first argument that looks
    /// like a path to a real file (skips the interpreter, e.g. `/bin/bash`).
    var scriptPath: String? {
        programArguments.first { $0.hasPrefix("/") && $0.contains("/") && !$0.hasPrefix("/bin/") && !$0.hasPrefix("/usr/") }
            ?? programArguments.first { $0.hasPrefix("/") }
    }
}

enum LaunchAgentPlist {

    /// Parse a plist dictionary (as read from disk) into an ``AgentDescriptor``.
    /// Returns nil when there's no usable `Label`.
    static func parse(_ dict: [String: Any]) -> AgentDescriptor? {
        guard let label = dict["Label"] as? String, !label.isEmpty else { return nil }
        let args = (dict["ProgramArguments"] as? [String])
            ?? (dict["Program"] as? String).map { [$0] }
            ?? []
        let env = (dict["EnvironmentVariables"] as? [String: String]) ?? [:]
        return AgentDescriptor(
            label: label,
            programArguments: args,
            startInterval: dict["StartInterval"] as? Int,
            stdoutPath: dict["StandardOutPath"] as? String,
            stderrPath: dict["StandardErrorPath"] as? String,
            runAtLoad: (dict["RunAtLoad"] as? Bool) ?? false,
            environment: env
        )
    }

    /// Read + parse a plist file. Returns nil if missing/unreadable/malformed.
    static func read(path: String) -> AgentDescriptor? {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { return nil }
        return parse(dict)
    }

    /// Parse plist *bytes* (e.g. fetched from a remote host via `cat <plist>` over SSH).
    /// `PropertyListSerialization` reads both XML and binary plists, so the raw file can be
    /// streamed back as-is — no `plutil` conversion needed on the remote. Nil if unparseable.
    static func parse(data: Data) -> AgentDescriptor? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return parse(dict)
    }

    /// Return a copy of `dict` with `StartInterval` set to `seconds` — the only
    /// key a schedule change should touch. Everything else (args, env, log paths)
    /// is preserved verbatim so an operational plist isn't disturbed.
    static func withStartInterval(_ dict: [String: Any], seconds: Int) -> [String: Any] {
        var out = dict
        out["StartInterval"] = seconds
        return out
    }
}
