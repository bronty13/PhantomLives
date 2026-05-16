import SwiftUI

/// Type-list sidebar — single nav primitive per the design.
/// Phase 2 implementation: types only. Saved views, search, and sync
/// status come later in Phase 2 / Phase 3.
struct Sidebar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

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
                // Tags Increment 3b — Search opens its own window
                // rather than taking over the detail pane, so it
                // sits here as a button (no `.tag()` → not a List
                // selection target). Keyboard shortcut ⌘⇧F is wired
                // separately via `SearchMenuItem`.
                Button {
                    openWindow(id: "search")
                } label: {
                    Label {
                        Text("Search")
                    } icon: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)

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
            if appState.vaultRevealed {
                let vaultTypes = appState.schema.visibleVaultTypes
                Section {
                    ForEach(vaultTypes) { type in
                        typeRow(type)
                            .tag(type.id)
                    }
                    if vaultTypes.isEmpty {
                        Label {
                            Text("Open the schema library to import Vault types.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } icon: {
                            EmptyView()
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .imageScale(.small)
                        Text("Vault")
                        Spacer()
                        Button {
                            appState.lockVault()
                        } label: {
                            Image(systemName: "lock")
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .help("Lock Vault")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PurpleLife")
        .onAppear { reloadCounts() }
        .onChange(of: appState.objectCount) { _, _ in reloadCounts() }
        .onChange(of: appState.vaultRevealed) { _, _ in reloadCounts() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                actionButtonsRow
                syncStatusFooter
            }
        }
    }

    /// Icon row above the sync footer — quick access to the four
    /// surfaces a user reaches for most: Schema editor, Find, Quick
    /// switcher, and (when the Vault is open) an instant Lock. Same
    /// shortcuts as the View / Window menu items, so the buttons are
    /// purely a discoverability + ergonomics layer; the keyboard
    /// shortcuts stay the canonical path.
    @ViewBuilder
    private var actionButtonsRow: some View {
        HStack(spacing: 14) {
            Button {
                openWindow(id: "schema-editor")
            } label: {
                Image(systemName: "square.grid.3x3.square")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Schema editor (⇧⌘S)")

            Button {
                openWindow(id: "search")
            } label: {
                Image(systemName: "magnifyingglass")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Find (⌘⇧F)")

            Button {
                openWindow(id: "quick-switcher")
            } label: {
                Image(systemName: "command")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Quick switcher (⌘K)")

            Spacer()

            if appState.vaultRevealed {
                Button {
                    appState.lockVault()
                } label: {
                    Image(systemName: "lock.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Lock Vault (⇧⌘V)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
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
        if appState.vaultRevealed {
            for t in appState.schema.visibleVaultTypes {
                next[t.id] = (try? appState.database.objectCount(typeId: t.id)) ?? 0
            }
        }
        countCache = next
    }
}

// `Color(hex:)` lives in `Models/PurpleTheme.swift` — that parser handles
// `#RGB`, `#RRGGBB`, and `#AARRGGBB` (the 8-digit form is needed by
// UserTheme to round-trip alpha-on-base slot colors). The schema's
// `colorHex` strings remain 6-digit; the same initializer handles both.
