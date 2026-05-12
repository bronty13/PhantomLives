import SwiftUI

/// Editorial top-bar chrome that replaces the macOS sidebar.
///
/// Layout: [220 brand] | [1fr horizontal tabs] | [auto right widget].
/// Each tab is `AppState.Section` aware and writes the selection back on click.
struct TopTabBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var now = Date()
    private let tickTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Visible tab order in the bar. `.importView` is intentionally excluded —
    /// it's reachable via the File → Import menu (⌘⇧I) and the wizard navigates
    /// itself when invoked.
    private static let visibleTabs: [AppState.Section] = [
        .dashboard, .editingQueue, .postingQueue, .clips,
        .calendar, .postingBatch, .reports, .c4sHistorical,
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brand
                    .frame(width: 220)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { EdHairline().frame(width: 1, height: nil) }
                tabs
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                rightWidget
                    .padding(.horizontal, 22)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 56)
            EdHairline()
        }
        .background(EdColor.bone)
        .onReceive(tickTimer) { now = $0 }
    }

    // MARK: - Brand

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(EdColor.ink).frame(width: 26, height: 26)
                Text("M")
                    .font(EdFont.serif(18, weight: .bold))
                    .foregroundStyle(EdColor.bone)
            }
            Text("MasterClipper")
                .font(EdFont.serif(18, weight: .bold))
                .tracking(-0.09)
                .foregroundStyle(EdColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Self.visibleTabs, id: \.self) { section in
                tab(for: section)
            }
            Spacer(minLength: 0)
        }
    }

    private func tab(for section: AppState.Section) -> some View {
        let active = appState.selectedSection == section
        let badge = badgeText(for: section)
        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Text(shortLabel(for: section))
                    .font(EdFont.sans(12.5, weight: .medium))
                    .tracking(0.06)
                if let badge {
                    Text(badge)
                        .font(EdFont.mono(10.5))
                        .foregroundStyle(active ? EdColor.bone.opacity(0.9) : EdColor.ink(0.6))
                }
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
            .foregroundStyle(active ? EdColor.bone : EdColor.ink)
            .background(active ? EdColor.ink : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle().fill(EdColor.ink(0.12)).frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(EdColor.acid).frame(height: 3).offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }

    private func shortLabel(for section: AppState.Section) -> String {
        switch section {
        case .dashboard:     return "Dashboard"
        case .editingQueue:  return "Editing"
        case .postingQueue:  return "Posting"
        case .clips:         return "Clips"
        case .calendar:      return "Calendar"
        case .postingBatch:  return "Batch"
        case .reports:       return "Reports"
        case .c4sHistorical: return "C4S Hist."
        case .importView:    return "Import"
        case .creatorImport: return "Creator Import"
        }
    }

    private func badgeText(for section: AppState.Section) -> String? {
        let n: Int
        switch section {
        case .clips:
            n = appState.clips.filter { !$0.archived }.count
        case .editingQueue:
            n = appState.clips.filter {
                !$0.archived &&
                ($0.statusEnum == .new || $0.statusEnum == .editing || $0.statusEnum == .toPost)
            }.count
        case .postingQueue:
            n = appState.clips.filter {
                !$0.archived && ($0.statusEnum == .toPost || $0.statusEnum == .posting)
            }.count
        case .c4sHistorical:
            n = (try? DatabaseService.shared.c4sHistoricalCount()) ?? 0
        default:
            return nil
        }
        guard n > 0 else { return nil }
        return n < 100 ? String(format: "%02d", n) : "\(n)"
    }

    // MARK: - Right widget

    private var rightWidget: some View {
        HStack(spacing: 14) {
            Text(clockText)
                .font(EdFont.mono(11))
                .foregroundStyle(EdColor.ink(0.6))
                .tracking(0.6)
            Button {
                NotificationCenter.default.post(name: .newClipRequested, object: nil)
            } label: {
                Text("⌘ N · NEW")
            }
            .buttonStyle(EdInkPillButtonStyle())
            .help("Create a new clip (⌘N)")
        }
    }

    private var clockText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · dd MMM yyyy · HH:mm"
        return f.string(from: now).uppercased()
    }
}
