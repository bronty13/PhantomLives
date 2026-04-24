import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                WatchHitBanner(watchlist: model.watchlist)
                    .animation(.spring(duration: 0.25), value: model.watchlist.recentHits.first?.id)
                if let id = model.selectedBufferID,
                   let idx = model.buffers.firstIndex(where: { $0.id == id }) {
                    BufferView(bufferIndex: idx)
                } else {
                    ConnectFormView()
                        .padding(24)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ConnectionStatusView()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showSetup = true
                } label: {
                    Label("Setup", systemImage: "gearshape")
                }
                .help("Servers, address book, and saved channels (⌘,)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showWatchlist = true
                } label: {
                    Label(model.watchlist.recentHits.isEmpty ? "Watchlist" : "Watchlist (\(model.watchlist.recentHits.count))",
                          systemImage: model.watchlist.recentHits.isEmpty ? "bell.badge" : "bell.badge.fill")
                }
                .help("Alert me when watched users come online")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.connectionState == .connected {
                        model.disconnect()
                    } else {
                        model.connect()
                    }
                } label: {
                    Label(model.connectionState == .connected ? "Disconnect" : "Connect",
                          systemImage: model.connectionState == .connected ? "bolt.slash" : "bolt")
                }
            }
        }
        .sheet(isPresented: $model.showRawLog) {
            RawLogView()
        }
        .sheet(isPresented: $model.showWatchlist) {
            WatchlistView(watchlist: model.watchlist)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showSetup) {
            SetupView(settings: model.settings)
                .environmentObject(model)
        }
    }
}

struct ConnectionStatusView: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var color: Color {
        switch model.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }
    private var label: String {
        switch model.connectionState {
        case .connected: return "connected as \(model.nick)"
        case .connecting: return "connecting…"
        case .failed(let err): return "failed: \(err)"
        case .disconnected: return "offline"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        List(selection: Binding(
            get: { model.selectedBufferID },
            set: { if let v = $0 { model.selectBuffer(v) } }
        )) {
            Section("Server") {
                ForEach(model.buffers.filter { $0.kind == .server }) { buf in
                    Label(buf.name, systemImage: "server.rack").tag(buf.id as Buffer.ID?)
                }
            }
            let channels = model.buffers.filter { $0.kind == .channel }
            if !channels.isEmpty {
                Section("Channels") {
                    ForEach(channels) { buf in
                        bufferRow(buf, icon: "number")
                    }
                }
            }
            let queries = model.buffers.filter { $0.kind == .query }
            if !queries.isEmpty {
                Section("Private") {
                    ForEach(queries) { buf in
                        bufferRow(buf, icon: "person.fill")
                    }
                }
            }

            let saved = savedForCurrentServer
            if !saved.isEmpty {
                Section("Saved") {
                    ForEach(saved) { ch in
                        Button {
                            model.quickJoin(ch.name)
                        } label: {
                            HStack {
                                Image(systemName: "number.square")
                                    .foregroundStyle(Color.accentColor)
                                Text(ch.name)
                                if !ch.note.isEmpty {
                                    Text("— \(ch.note)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let addresses = model.settings.settings.addressBook
            if !addresses.isEmpty {
                Section("Contacts") {
                    ForEach(addresses) { a in
                        Button {
                            model.sendInput("/msg \(a.nick) ")
                        } label: {
                            HStack {
                                Circle()
                                    .fill(contactColor(for: a))
                                    .frame(width: 8, height: 8)
                                Text(a.nick)
                                    .font(.system(.body, design: .monospaced))
                                if a.watch {
                                    Image(systemName: "bell.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.purple)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooterView()
        }
    }

    private var savedForCurrentServer: [SavedChannel] {
        let sid = model.settings.settings.selectedServerID
        return model.settings.settings.savedChannels.filter {
            $0.serverID == nil || $0.serverID == sid
        }
    }

    private func contactColor(for entry: AddressEntry) -> Color {
        guard entry.watch else { return .gray }
        switch model.watchlist.presence[entry.nick.lowercased()] ?? .unknown {
        case .online: return .green
        case .offline: return .gray
        case .unknown: return .yellow
        }
    }

    @ViewBuilder
    private func bufferRow(_ buf: Buffer, icon: String) -> some View {
        HStack {
            Label(buf.name, systemImage: icon)
            Spacer()
            if buf.unread > 0 {
                Text("\(buf.unread)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .tag(buf.id as Buffer.ID?)
    }
}

struct SidebarFooterView: View {
    @EnvironmentObject var model: ChatModel
    @State private var joinTarget: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                TextField("Join #channel", text: $joinTarget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(join)
                Button("Join", action: join)
                    .disabled(model.connectionState != .connected || joinTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
    }
    private func join() {
        let t = joinTarget.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let name = t.hasPrefix("#") ? t : "#" + t
        model.sendInput("/join \(name)")
        joinTarget = ""
    }
}

struct ConnectFormView: View {
    @EnvironmentObject var model: ChatModel

    var body: some View {
        VStack(spacing: 16) {
            if model.settings.settings.servers.isEmpty {
                ContentUnavailableView(
                    "No servers configured",
                    systemImage: "server.rack",
                    description: Text("Open Setup (⌘,) to add a server profile.")
                )
                Button("Open Setup") { model.showSetup = true }
                    .keyboardShortcut(.defaultAction)
            } else {
                Form {
                    Section("Server profile") {
                        Picker("Profile", selection: Binding(
                            get: { model.settings.settings.selectedServerID ?? model.settings.settings.servers.first!.id },
                            set: { model.settings.settings.selectedServerID = $0 }
                        )) {
                            ForEach(model.settings.settings.servers) { s in
                                Text(s.name).tag(s.id)
                            }
                        }
                        if let p = model.settings.selectedServer() {
                            LabeledContent("Host") { Text("\(p.host):\(p.port)") }
                            LabeledContent("TLS") { Text(p.useTLS ? "yes" : "no") }
                            LabeledContent("Nickname") { Text(p.nick) }
                            if !p.autoJoin.isEmpty {
                                LabeledContent("Auto-join") { Text(p.autoJoin).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Button("Edit in Setup…") { model.showSetup = true }
                    Spacer()
                    Button("Connect") { model.connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.connectionState == .connecting || model.connectionState == .connected)
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: 520)
    }
}
