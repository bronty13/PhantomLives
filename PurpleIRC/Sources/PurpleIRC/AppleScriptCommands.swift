import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// AppleScript bridge for PurpleIRC.
///
/// macOS's `Cocoa Scripting` machinery instantiates one of these subclasses
/// per scripting verb — they're matched up by class name in the .sdef file.
/// Each subclass overrides `performDefaultImplementation()` to do the work
/// and return a string result the script can capture.
///
/// All commands route through the singleton ChatModel via the
/// `AppleScriptBridge.host` weak reference; ChatModel sets that on init so
/// these classes don't need to know how to construct a model.
///
/// The whole bridge is gated behind `NSAppleScriptEnabled = YES` and an
/// `OSAScriptingDefinition` key in Info.plist; both are written in
/// `build-app.sh` when the bundle is assembled.

/// Shared host for AppleScript commands. ChatModel's init wires `host = self`
/// so verbs can reach the live model. Weak so the model can still be
/// deallocated in tests / preview builds.
@MainActor
enum AppleScriptBridge {
    private(set) static weak var host: ChatModel?
    static func register(host: ChatModel) {
        Self.host = host
    }
}

/// Helper — every command needs the same `host or fail` boilerplate. Pulled
/// into one place so commands stay tiny.
private func chatHost() -> ChatModel? {
    // AppleScript commands run on the main thread; ChatModel is @MainActor.
    // We assume the assumption holds in apple-event dispatch (it does in
    // practice on macOS 14+).
    MainActor.assumeIsolated { AppleScriptBridge.host }
}

@MainActor
private func runOnMain(_ block: () -> String) -> String {
    if Thread.isMainThread {
        return block()
    } else {
        var result = ""
        DispatchQueue.main.sync { result = block() }
        return result
    }
}

// MARK: - Commands

/// `tell application "PurpleIRC" to connect`
final class PurpleConnectCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        MainActor.assumeIsolated {
            host.connect()
        }
        return "Connect requested."
    }
}

/// `tell application "PurpleIRC" to disconnect with reason "bye"`
/// The reason is currently ignored — `ChatModel.disconnect()` takes no
/// arguments and the active connection emits a default QUIT. Kept on the
/// command so scripts written against the dictionary stay well-formed.
final class PurpleDisconnectCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        MainActor.assumeIsolated {
            host.disconnect()
        }
        return "Disconnect requested."
    }
}

/// `tell application "PurpleIRC" to send message "hello" to "#swift"`
final class PurpleSendMessageCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        let body = directParameter as? String ?? ""
        guard let target = evaluatedArguments?["target"] as? String, !target.isEmpty else {
            return "Missing target — use `to \"#channel\"` or `to \"nick\"`."
        }
        guard !body.isEmpty else { return "Empty message body." }
        MainActor.assumeIsolated {
            host.sendInput("/msg \(target) \(body)")
        }
        return "Sent to \(target)."
    }
}

/// `tell application "PurpleIRC" to join channel "#swift"`
final class PurpleJoinCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        let chan = (directParameter as? String) ?? ""
        guard !chan.isEmpty else { return "Empty channel name." }
        let normalized = chan.hasPrefix("#") ? chan : "#" + chan
        MainActor.assumeIsolated {
            host.sendInput("/join \(normalized)")
        }
        return "Joined \(normalized)."
    }
}

/// `tell application "PurpleIRC" to part channel "#swift" with reason "lunch"`
final class PurplePartCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        let chan = (directParameter as? String) ?? ""
        guard !chan.isEmpty else { return "Empty channel name." }
        let reason = evaluatedArguments?["reason"] as? String
        let line: String
        if let reason, !reason.isEmpty {
            line = "/part \(chan) \(reason)"
        } else {
            line = "/part \(chan)"
        }
        MainActor.assumeIsolated {
            host.sendInput(line)
        }
        return "Parted \(chan)."
    }
}

/// `tell application "PurpleIRC" to get current nickname`
final class PurpleCurrentNickCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "" }
        return MainActor.assumeIsolated { host.nick }
    }
}

/// `tell application "PurpleIRC" to say in active buffer "lunch break"`
/// — sends to the currently selected channel/query without naming a target.
final class PurpleSayCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = chatHost() else { return "PurpleIRC not ready." }
        let body = (directParameter as? String) ?? ""
        guard !body.isEmpty else { return "Empty message body." }
        MainActor.assumeIsolated {
            host.sendInput(body)
        }
        return "Sent."
    }
}
