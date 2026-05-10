import SwiftUI

/// Type-list sidebar — single nav primitive per the design.
/// Phase 2 implementation: types only. Saved views, search, and sync
/// status come later in Phase 2 / Phase 3.
struct Sidebar: View {
    @EnvironmentObject private var appState: AppState

    /// "today" sentinel for selection — String? doesn't let us tell apart
    /// "no selection" from "Today is selected", so we use a magic value.
    private static let todaySelection = "__purplelife.today"

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { appState.showTodayInDetail ? Self.todaySelection : appState.selectedTypeId },
            set: { newValue in
                if newValue == Self.todaySelection {
                    appState.showTodayInDetail = true
                    appState.selectedTypeId = nil
                } else {
                    appState.showTodayInDetail = false
                    appState.selectedTypeId = newValue
                }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                Label {
                    Text("Today")
                } icon: {
                    Image(systemName: "sun.max")
                        .foregroundStyle(.tint)
                }
                .tag(Self.todaySelection)
            }
            Section("Types") {
                ForEach(appState.schema.visibleTypes) { type in
                    typeRow(type)
                        .tag(type.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PurpleLife")
        .onAppear { reloadCounts() }
        .onChange(of: appState.objectCount) { _, _ in reloadCounts() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            syncStatusFooter
        }
    }

    @ViewBuilder
    private var syncStatusFooter: some View {
        let sync = appState.sync
        HStack(spacing: 6) {
            Image(systemName: sync.status.systemImage)
                .foregroundStyle(footerColor(for: sync.status))
                .imageScale(.small)
            Text(sync.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                sync.syncNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Sync now")
            .disabled(sync.status == .disabled || sync.status == .notSignedIn)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func footerColor(for status: CloudKitSyncService.Status) -> Color {
        switch status {
        case .idle:                       return .green
        case .syncing, .settingUp:        return .accentColor
        case .error:                      return .red
        case .notSignedIn, .disabled:     return .secondary
        }
    }

    @ViewBuilder
    private func typeRow(_ type: ObjectType) -> some View {
        Label {
            HStack {
                Text(type.pluralName)
                Spacer()
                if let count = countCache[type.id] {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: type.systemImage)
                .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
        }
    }

    @State private var countCache: [String: Int] = [:]

    private func reloadCounts() {
        var next: [String: Int] = [:]
        for t in appState.schema.visibleTypes {
            next[t.id] = (try? appState.database.objectCount(typeId: t.id)) ?? 0
        }
        countCache = next
    }
}

extension Color {
    /// Lenient hex parser for the schema's `colorHex` strings.
    /// Accepts `#RRGGBB` or `RRGGBB`. Returns `nil` on bad input rather
    /// than substituting a fallback — callers decide what default to use.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double( v        & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
