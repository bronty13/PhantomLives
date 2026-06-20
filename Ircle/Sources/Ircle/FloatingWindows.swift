import SwiftUI
import AppKit

// The "Floating" interface style recreates classic Ircle 3.5's separate-windows
// layout: a Console window, a window per channel/query, a detached Userlist
// (nick list) window, and a floating Inputline window. They coordinate through
// the single piece of shared state `model.selectedBuffer` — focusing any window
// selects its buffer; the Console / Userlist / Inputline all re-target to it.

/// Root of the primary window. Renders the integrated `ContentView` in
/// Clean/Classic, or the Console in Floating — and, in Floating, opens/closes
/// the rest of the window constellation as the style and buffer set change.
struct RootView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var openBufferWindows: Set<UUID> = []

    private var style: InterfaceStyle { settingsStore.settings.interfaceStyle }
    /// Channels and queries get their own windows; server buffers live only in
    /// the primary Console window (so no buffer is ever shown twice).
    private var detachableBuffers: [IrcleBuffer] { model.allBuffers.filter { $0.kind != .server } }

    var body: some View {
        Group {
            if style == .floating { FloatingConsoleView() }
            else { ContentView() }
        }
        .onAppear { sync(to: style) }
        .onChange(of: style) { _, new in sync(to: new) }
        .onChange(of: detachableBuffers.map(\.id)) { _, _ in reconcileBufferWindows() }
    }

    /// Open or tear down the constellation when the interface style changes.
    /// The opens are deferred to the next runloop tick: calling `openWindow`
    /// synchronously while the primary window is mid-transition (ContentView →
    /// FloatingConsoleView) can drop the singleton Userlist/Inputline windows.
    private func sync(to style: InterfaceStyle) {
        if style == .floating {
            DispatchQueue.main.async {
                openWindow(id: "userlist")
                openWindow(id: "inputline")
                reconcileBufferWindows()
            }
        } else {
            dismissWindow(id: "userlist")
            dismissWindow(id: "inputline")
            for id in openBufferWindows { dismissWindow(id: "buffer", value: id) }
            openBufferWindows = []
        }
    }

    /// Open a window for each new channel/query; dismiss windows for buffers that
    /// have closed. Diffed against `openBufferWindows` so we never steal focus by
    /// re-opening windows that already exist.
    private func reconcileBufferWindows() {
        guard style == .floating else { return }
        let want = Set(detachableBuffers.map(\.id))
        for id in want.subtracting(openBufferWindows) { openWindow(id: "buffer", value: id) }
        for id in openBufferWindows.subtracting(want) { dismissWindow(id: "buffer", value: id) }
        openBufferWindows = want
    }
}

/// The primary window in Floating mode: the Console (server messages) of the
/// active session, with the classic bottom status strip. Follows the selected
/// session, so switching channels switches which network's console is shown.
struct FloatingConsoleView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        let palette = settingsStore.palette
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                MessageListView(buffer: session.serverBuffer, palette: palette,
                                fontSize: settingsStore.settings.fontSize,
                                showTimestamps: settingsStore.settings.showTimestamps)
                Divider().overlay(palette.hairline)
                BufferStatusStrip(buffer: session.serverBuffer, palette: palette)
            } else {
                WelcomePane(palette: palette)
            }
        }
        .background(palette.windowBG)
        .frame(minWidth: 480, minHeight: 320)
    }
}

/// One window per channel/query: topic bar + messages + the classic bottom
/// status strip. Becoming the key window selects this buffer, so the shared
/// Userlist + Inputline re-target to it.
struct BufferWindowView: View {
    let bufferID: UUID
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore

    private var buffer: IrcleBuffer? { model.allBuffers.first { $0.id == bufferID } }

    var body: some View {
        let palette = settingsStore.palette
        Group {
            if let buffer {
                VStack(spacing: 0) {
                    TopicBar(buffer: buffer, palette: palette)
                    Divider().overlay(palette.hairline)
                    MessageListView(buffer: buffer, palette: palette,
                                    fontSize: settingsStore.settings.fontSize,
                                    showTimestamps: settingsStore.settings.showTimestamps)
                    Divider().overlay(palette.hairline)
                    BufferStatusStrip(buffer: buffer, palette: palette)
                }
                .background(palette.windowBG)
                .frame(minWidth: 400, minHeight: 280)
                .background(WindowAccessor(title: title(buffer)) { model.select(buffer) })
            } else {
                // Buffer closed: a blank pane until the window is dismissed.
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private func title(_ buffer: IrcleBuffer) -> String {
        let net = model.session(for: buffer)?.displayName
        return net.map { "\(buffer.name) — \($0)" } ?? buffer.name
    }
}

/// The detached nick-list window — binds to the selected channel. Reuses
/// `NickListView` (the Classic action grid + `t n i p s m l k r` mode row).
struct UserlistWindowView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        let palette = settingsStore.palette
        Group {
            if let buffer = model.selectedBuffer, buffer.kind == .channel {
                NickListView(buffer: buffer, palette: palette, hostnameColumns: true)
            } else {
                VStack {
                    Spacer()
                    Text("Select a channel to see its users.")
                        .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.paneBG)
            }
        }
        .frame(minWidth: 300, minHeight: 240)
        .background(WindowAccessor(title: userlistTitle))
    }

    private var userlistTitle: String {
        guard let b = model.selectedBuffer, b.kind == .channel else { return "Userlist" }
        return "\(b.name): \(b.users.count) user\(b.users.count == 1 ? "" : "s")"
    }
}

/// The detached floating Inputline window — binds to the selected buffer. Reuses
/// `InputBarView` (the formatting toolbar + "talking to X").
struct InputlineWindowView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        let palette = settingsStore.palette
        Group {
            if let buffer = model.selectedBuffer {
                InputBarView(buffer: buffer, palette: palette)
            } else {
                HStack {
                    Text("Not connected.").font(palette.chromeFont())
                        .foregroundColor(palette.timestamp)
                    Spacer()
                }
                .padding(10)
                .background(palette.paneBG)
            }
        }
        .frame(minWidth: 380)
        .background(WindowAccessor(title: "Inputline"))
    }
}

/// The classic per-window bottom strip: "Nick: <nick>  Server: <network>".
struct BufferStatusStrip: View {
    @EnvironmentObject var model: IrcleModel
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette

    var body: some View {
        let session = model.session(for: buffer)
        HStack(spacing: 6) {
            Text("Nick:").font(palette.chromeFontBold()).foregroundColor(palette.chromeText)
            Text(session?.nick ?? "—").font(palette.chromeFont()).foregroundColor(palette.chromeText)
            Spacer().frame(width: 10)
            Text("Server:").font(palette.chromeFontBold()).foregroundColor(palette.chromeText)
            Text(session?.displayName ?? "—").font(palette.chromeFont()).foregroundColor(palette.timestamp)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .platinumBevel(palette, raised: false, fill: palette.paneBG)
    }
}

// MARK: - Window access (titling + key-window → selection)

/// Bridges to the hosting `NSWindow` to set its title and, optionally, run a
/// closure when it becomes the key window (used to select a buffer on focus).
struct WindowAccessor: NSViewRepresentable {
    var title: String?
    var onBecomeKey: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: v, title: title, onBecomeKey: onBecomeKey) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onBecomeKey = onBecomeKey
        if let title { DispatchQueue.main.async { nsView.window?.title = title } }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onBecomeKey: (() -> Void)?
        private var token: NSObjectProtocol?

        func attach(to view: NSView, title: String?, onBecomeKey: (() -> Void)?) {
            self.onBecomeKey = onBecomeKey
            guard let window = view.window else { return }
            if let title { window.title = title }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onBecomeKey?() }
        }

        func detach() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}
