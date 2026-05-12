import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .servers

    /// Adopt any one-shot tab directive (e.g. the Identity toolbar menu's
    /// "Manage identities…" button) so the sheet opens on the right tab
    /// instead of always landing on Servers.
    private func consumePendingTab() {
        if let req = model.pendingSetupTab {
            tab = req
            model.pendingSetupTab = nil
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case servers      = "Servers"
        case identities   = "Identities"
        case proxyDcc     = "Proxy & DCC"
        case addressBook  = "Address Book"
        case channels     = "Channels"
        case ignores      = "Ignore"
        case highlights   = "Highlights"
        case behavior     = "Behavior"
        case notifications = "Notifications"
        case logging      = "Logging"
        case appearance   = "Appearance"
        case themes       = "Themes"
        case fonts        = "Fonts"
        case sounds       = "Sounds"
        case bot          = "Bot"
        case scripts      = "PurpleBot"
        case assistant    = "Assistant"
        case shortcuts    = "Shortcuts & Aliases"
        case backup       = "Backup"
        case security     = "Security"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .servers:       return "server.rack"
            case .identities:    return "person.2.wave.2"
            case .proxyDcc:      return "network"
            case .addressBook:   return "person.crop.rectangle.stack"
            case .channels:      return "number"
            case .ignores:       return "nosign"
            case .highlights:    return "sparkles"
            case .behavior:      return "slider.horizontal.3"
            case .notifications: return "bell.badge"
            case .logging:       return "doc.text"
            case .appearance:    return "paintpalette"
            case .themes:        return "swatchpalette"
            case .fonts:         return "textformat"
            case .sounds:        return "speaker.wave.2"
            case .bot:           return "bolt.badge.a"
            case .scripts:       return "curlybraces"
            case .assistant:     return "brain"
            case .shortcuts:     return "command"
            case .backup:        return "externaldrive.badge.timemachine"
            case .security:      return "lock.shield"
            }
        }
    }

    /// Logical grouping used by the sidebar — six sections, mirroring
    /// macOS System Settings. A segmented bar at 20 tabs would be
    /// unreadable; a sectioned sidebar scales indefinitely.
    private static let groups: [(String, [Tab])] = [
        ("Connections",     [.servers, .identities, .proxyDcc]),
        ("People & places", [.addressBook, .channels, .ignores, .highlights]),
        ("Behavior",        [.behavior, .notifications, .logging]),
        ("Personalization", [.appearance, .themes, .fonts, .sounds]),
        ("Power-user",      [.bot, .scripts, .assistant, .shortcuts, .backup]),
        ("Security",        [.security]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear { consumePendingTab() }
        // The sheet may already be showing when a different tab gets
        // requested (e.g. user has Setup open, clicks the toolbar Identity
        // menu's "Manage identities…"). Watching the published value flips
        // the tab even on already-mounted sheets.
        .onChange(of: model.pendingSetupTab) { _, _ in consumePendingTab() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .font(.title2)
                .foregroundStyle(Color.purple)
            Text("PurpleIRC Setup").font(.title3.weight(.semibold))
            Text("v\(AppVersion.short)")
                .font(.caption).foregroundStyle(.secondary)
                .help("Build \(AppVersion.build)")
            Spacer()
            Text(settings.fileURLForDisplay)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .truncationMode(.middle)
                .lineLimit(1)
            Button("Done") { model.showSetup = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var sidebar: some View {
        List(selection: $tab) {
            ForEach(Self.groups, id: \.0) { (title, tabs) in
                Section(title) {
                    ForEach(tabs) { t in
                        Label(t.rawValue, systemImage: t.systemImage).tag(t)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
    }

    @ViewBuilder
    private var content: some View {
        // No outer ScrollView — Form-based tabs (.appearance, .behavior,
        // .security, .scripts, .ignores, .channels, .addressBook detail)
        // scroll natively via .formStyle(.grouped). Master/detail tabs
        // (.servers, .identities, .highlights, .bot, .addressBook) need
        // their full sheet height so the bottom +/− toolbar stays
        // reachable instead of being pushed below the scroll edge by
        // a long list.
        Group {
            switch tab {
            case .servers:       ServersSetup(settings: settings)
            case .identities:    IdentitiesSetup(settings: settings)
            case .proxyDcc:      ProxyDccSetup(settings: settings)
            case .security:      SecuritySetup(settings: settings, keyStore: model.keyStore)
            case .addressBook:   AddressBookSetup(settings: settings)
            case .channels:      ChannelsSetup(settings: settings)
            case .ignores:       IgnoreSetup(settings: settings)
            case .highlights:    HighlightsSetup(settings: settings)
            case .bot:           BotSetup(settings: settings, engine: model.botEngine)
            case .appearance:    AppearanceSetup(settings: settings)
            case .themes:        ThemesSetup(settings: settings)
            case .fonts:         FontsSetup(settings: settings)
            case .sounds:        SoundsSetup(settings: settings)
            case .behavior:      BehaviorSetup(settings: settings)
            case .notifications: NotificationsSetup(settings: settings)
            case .logging:       LoggingSetup(settings: settings)
            case .assistant:     AssistantSetup(settings: settings)
            case .shortcuts:     ShortcutsAliasesSetup(settings: settings)
            case .backup:        BackupSetup(settings: settings)
            case .scripts:       ScriptsSetup(bot: model.bot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

