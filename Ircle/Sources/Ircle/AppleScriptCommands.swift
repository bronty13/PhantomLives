import Foundation
import IRCKit

/// Bridges AppleScript commands to the live `IrcleModel`. The model registers
/// itself on launch so command objects (which Cocoa Scripting instantiates) can
/// find it. Weak so it never keeps the model alive.
@MainActor
enum IrcleAppleScriptBridge {
    private(set) static weak var host: IrcleModel?
    static func register(host: IrcleModel) { Self.host = host }
}

/// Apple events are delivered on the main thread; reach the @MainActor model.
private func ircleHost() -> IrcleModel? {
    MainActor.assumeIsolated { IrcleAppleScriptBridge.host }
}

// Each command needs an explicit `@objc(...)` Obj-C name: Cocoa Scripting
// resolves the .sdef's `<cocoa class="..."/>` via `NSClassFromString`, and
// Swift would otherwise export a module-mangled name ("Ircle.IrcleConnectCommand")
// that the lookup can't find (AppleScript error -1717, handler not found).

/// `connect` — connect to the default (first) saved server.
@objc(IrcleConnectCommand)
final class IrcleConnectCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = ircleHost() else { return "Ircle is not ready." }
        return MainActor.assumeIsolated {
            host.connectDefault()
            return "Connecting…"
        }
    }
}

/// `join channel "#name"` — JOIN on the active server.
@objc(IrcleJoinCommand)
final class IrcleJoinCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = ircleHost() else { return "Ircle is not ready." }
        let chan = IRCSanitize.field((directParameter as? String) ?? "")
        guard !chan.isEmpty else { return "Empty channel name." }
        let normalized = (chan.hasPrefix("#") || chan.hasPrefix("&")) ? chan : "#" + chan
        return MainActor.assumeIsolated {
            guard let session = host.selectedSession else { return "Not connected." }
            session.runCommand("/join \(normalized)", in: session.serverBuffer)
            return "Joining \(normalized)."
        }
    }
}

/// `say "text" [to "#channel"|"nick"]` — message a target, or the active buffer.
@objc(IrcleSayCommand)
final class IrcleSayCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = ircleHost() else { return "Ircle is not ready." }
        let body = IRCSanitize.field((directParameter as? String) ?? "")
        guard !body.isEmpty else { return "Empty message." }
        let rawTarget = evaluatedArguments?["target"] as? String
        return MainActor.assumeIsolated {
            guard let session = host.selectedSession else { return "Not connected." }
            if let rawTarget, !rawTarget.isEmpty {
                let target = IRCSanitize.field(rawTarget)
                session.runCommand("/msg \(target) \(body)", in: session.serverBuffer)
                return "Sent to \(target)."
            }
            // No explicit target — use the active channel/query.
            guard let buffer = host.selectedBuffer, buffer.kind != .server else {
                return "No active channel — use `to \"#channel\"`."
            }
            session.sendText(body, to: buffer)
            return "Sent to \(buffer.name)."
        }
    }
}

/// `current nickname` — your nick on the active server.
@objc(IrcleCurrentNickCommand)
final class IrcleCurrentNickCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let host = ircleHost() else { return "" }
        return MainActor.assumeIsolated { host.selectedSession?.nick ?? "" }
    }
}
