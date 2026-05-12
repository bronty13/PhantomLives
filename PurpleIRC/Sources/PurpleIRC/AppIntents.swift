import AppIntents
import Foundation

// AppIntents framework — Shortcuts.app + Focus Filter integration.
//
// Every intent reaches the live `ChatModel` via the same singleton bridge
// the AppleScript commands use (`AppleScriptBridge.host`). Both surfaces
// dispatch on the main actor; the bridge weak-refs ChatModel so neither
// surface keeps the app alive past its natural lifetime.
//
// Shipping set (1.0.241):
//   • SetAwayIntent          — "Set Away in PurpleIRC"
//   • BackFromAwayIntent     — "Set Back from Away in PurpleIRC"
//   • SendIRCMessageIntent   — "Send IRC Message" (target + text)
//   • SayInActiveBufferIntent — "Say in PurpleIRC" (text only)
//   • PurpleIRCFocusFilter   — Focus Filter that hides selected networks
//
// All five surface under the app's name in Shortcuts.app + System Settings →
// Focus → Focus Filters via `PurpleIRCShortcuts: AppShortcutsProvider` at
// the bottom of this file.

@available(macOS 14.0, *)
struct SetAwayIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Away"
    static var description = IntentDescription("Mark yourself as away on the active IRC network. Equivalent to typing /away in the app.")

    @Parameter(title: "Reason", default: "Away")
    var reason: String

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let safeReason = IRCSanitize.field(reason)
        let line = safeReason.isEmpty ? "/away" : "/away \(safeReason)"
        AppleScriptBridge.host?.sendInput(line)
        return .result()
    }
}

@available(macOS 14.0, *)
struct BackFromAwayIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Back from Away"
    static var description = IntentDescription("Clear your away status on the active IRC network. Equivalent to typing /back in the app.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppleScriptBridge.host?.sendInput("/back")
        return .result()
    }
}

@available(macOS 14.0, *)
struct SendIRCMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send IRC Message"
    static var description = IntentDescription("Send a PRIVMSG to a channel or nick on the active network. The target can be a channel like #swift or a nickname.")

    @Parameter(title: "Target", description: "Channel like #swift or a nickname.")
    var target: String

    @Parameter(title: "Message")
    var text: String

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let safeTarget = IRCSanitize.field(target)
        let safeText = IRCSanitize.field(text)
        guard !safeTarget.isEmpty, !safeText.isEmpty else { return .result() }
        AppleScriptBridge.host?.sendInput("/msg \(safeTarget) \(safeText)")
        return .result()
    }
}

@available(macOS 14.0, *)
struct SayInActiveBufferIntent: AppIntent {
    static var title: LocalizedStringResource = "Say in Active Buffer"
    static var description = IntentDescription("Send a line to the currently-selected channel or query. No target needed — uses whatever buffer is in focus.")

    @Parameter(title: "Message")
    var text: String

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let safe = IRCSanitize.field(text)
        guard !safe.isEmpty else { return .result() }
        AppleScriptBridge.host?.sendInput(safe)
        return .result()
    }
}

/// Focus Filter — when the user assigns this to a Focus mode in System
/// Settings → Focus → Focus Filters, switching into that Focus invokes
/// `perform()` with the user's pre-configured network list. The active
/// list is parsed (one network name per line, case-insensitive) and
/// stashed on `ChatModel.focusFilterHiddenNetworks`; the sidebar
/// consults that set when drawing the Networks section so matching
/// connections vanish until the Focus turns off (which also fires
/// `perform()` with an empty list).
@available(macOS 14.0, *)
struct PurpleIRCFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "PurpleIRC Focus Filter"
    static var description: IntentDescription? = IntentDescription("Hide selected IRC networks from the sidebar while this Focus is active. Enter one network name per line — names match the display name shown in the sidebar Networks section, case-insensitive.")

    @Parameter(title: "Networks to hide",
               description: "One network name per line.",
               default: "")
    var hiddenNetworksText: String

    /// System Settings → Focus → Focus Filters renders this string under
    /// each configured filter so the user can tell at a glance what the
    /// filter is set to. Trimmed + newline-flattened for compactness.
    var displayRepresentation: DisplayRepresentation {
        let names = hiddenNetworksText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if names.isEmpty {
            return DisplayRepresentation(title: "Hide no IRC networks")
        }
        return DisplayRepresentation(
            title: "Hide \(names.count) IRC network\(names.count == 1 ? "" : "s")",
            subtitle: "\(names.joined(separator: ", "))")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let names = hiddenNetworksText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        AppleScriptBridge.host?.applyFocusFilter(hiddenNetworkNames: Set(names))
        return .result()
    }
}

@available(macOS 14.0, *)
struct PurpleIRCShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetAwayIntent(),
                    phrases: ["Set away in \(.applicationName)",
                              "Mark me away in \(.applicationName)"],
                    shortTitle: "Set Away",
                    systemImageName: "moon.zzz")
        AppShortcut(intent: BackFromAwayIntent(),
                    phrases: ["Mark me back in \(.applicationName)",
                              "Clear away in \(.applicationName)"],
                    shortTitle: "Set Back",
                    systemImageName: "sun.max")
        AppShortcut(intent: SendIRCMessageIntent(),
                    phrases: ["Send an IRC message with \(.applicationName)"],
                    shortTitle: "Send Message",
                    systemImageName: "paperplane")
        AppShortcut(intent: SayInActiveBufferIntent(),
                    phrases: ["Say something in \(.applicationName)"],
                    shortTitle: "Say",
                    systemImageName: "text.bubble")
    }
}
