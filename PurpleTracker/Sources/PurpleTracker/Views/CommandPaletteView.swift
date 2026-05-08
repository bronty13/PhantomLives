import SwiftUI

/// ⌘K palette — fuzzy-search across matters, people, initiatives, goals,
/// and quick actions. Press ↑/↓ to navigate, Enter to choose.
struct CommandPaletteView: View {
    @EnvironmentObject var app: AppState
    @State private var query: String = ""
    @State private var selected: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Matters, people, actions…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(activateSelected)
                    .onAppear { focused = true }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        Button { activate(item) } label: {
                            HStack {
                                Image(systemName: item.icon)
                                    .frame(width: 20)
                                    .foregroundStyle(item.tint)
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                    if let sub = item.subtitle {
                                        Text(sub).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(idx == selected ? Color.accentColor.opacity(0.2) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(KeyMonitor(
            up:    { selected = max(0, selected - 1) },
            down:  { selected = min(items.count - 1, selected + 1) },
            esc:   { app.commandPaletteVisible = false }
        ))
    }

    private struct Item {
        let title: String
        let subtitle: String?
        let icon: String
        let tint: Color
        let action: () -> Void
    }

    private var items: [Item] {
        let q = query.lowercased()
        var rows: [Item] = []

        // Quick actions
        let actions: [Item] = [
            Item(title: "Today",            subtitle: "Dashboard", icon: "sun.max",    tint: .orange) { app.sidebarSection = .today; close() },
            Item(title: "All Matters",      subtitle: nil,         icon: "tray.full",  tint: .accentColor) { app.sidebarSection = .all; close() },
            Item(title: "Time Dashboard",   subtitle: nil,         icon: "chart.bar",  tint: .purple)     { app.sidebarSection = .timeDashboard; close() },
            Item(title: "Analytics",        subtitle: nil,         icon: "chart.pie",  tint: .blue)       { app.sidebarSection = .analytics; close() },
            Item(title: "Capacity",         subtitle: nil,         icon: "person.3",   tint: .teal)       { app.sidebarSection = .capacity; close() },
            Item(title: "Trash",            subtitle: nil,         icon: "trash",      tint: .secondary)  { app.sidebarSection = .trash; close() },
            Item(title: "Toggle Active Timer", subtitle: nil,      icon: "timer",      tint: .red)        {
                if app.timer.activeMatterId != nil { _ = app.timer.stop() }
                else if let id = app.selectedMatterId { app.timer.start(matterId: id) }
                close()
            },
        ]
        rows += actions.filter { q.isEmpty || $0.title.lowercased().contains(q) }

        if !q.isEmpty {
            // Matters
            let matters = app.matters.filter {
                $0.title.lowercased().contains(q) || $0.id.lowercased().contains(q)
            }.prefix(15)
            for m in matters {
                rows.append(Item(
                    title: "\(m.id) — \(m.title.isEmpty ? "(untitled)" : m.title)",
                    subtitle: m.status,
                    icon: "doc.text",
                    tint: .accentColor
                ) { app.selectMatter(id: m.id); close() })
            }
            // People
            let people = app.people.filter {
                $0.displayName.lowercased().contains(q)
            }.prefix(10)
            for p in people {
                rows.append(Item(
                    title: p.displayName,
                    subtitle: p.jobTitle.isEmpty ? "Person" : p.jobTitle,
                    icon: "person.crop.circle",
                    tint: .blue
                ) { /* nothing to drill into yet */ close() })
            }
        }

        return rows
    }

    private func activateSelected() {
        guard items.indices.contains(selected) else { return }
        activate(items[selected])
    }

    private func activate(_ item: Item) {
        item.action()
    }

    private func close() {
        app.commandPaletteVisible = false
    }
}

/// AppKit bridge to capture arrow / escape keys while the palette is up.
private struct KeyMonitor: NSViewRepresentable {
    var up: () -> Void
    var down: () -> Void
    var esc: () -> Void

    final class Monitor: NSView {
        var up: () -> Void = {}
        var down: () -> Void = {}
        var esc: () -> Void = {}
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: up()
            case 125: down()
            case 53:  esc()
            default:  super.keyDown(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let v = Monitor()
        v.up = up; v.down = down; v.esc = esc
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let m = nsView as? Monitor { m.up = up; m.down = down; m.esc = esc }
    }
}
