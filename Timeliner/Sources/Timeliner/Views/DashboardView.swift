import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200), spacing: 12)
                ], spacing: 12) {
                    StatCard(
                        title: "Cases",
                        value: "\(appState.cases.count)",
                        systemImage: "folder.fill",
                        tint: .blue
                    )
                    StatCard(
                        title: "Active",
                        value: "\(appState.cases.filter { $0.statusEnum == .active }.count)",
                        systemImage: "flame.fill",
                        tint: .red
                    )
                    StatCard(
                        title: "Events",
                        value: "\(appState.events.count)",
                        systemImage: "calendar.badge.clock",
                        tint: .purple
                    )
                    StatCard(
                        title: "People",
                        value: "\(appState.people.count)",
                        systemImage: "person.2.fill",
                        tint: .green
                    )
                }

                if !pinnedCases.isEmpty {
                    section("Pinned") {
                        VStack(spacing: 8) {
                            ForEach(pinnedCases) { c in
                                CaseSummaryRow(aCase: c) {
                                    appState.selectedSection = .allCases
                                    appState.selectedCaseId = c.id
                                }
                            }
                        }
                    }
                }

                section("Recent activity") {
                    if recentEvents.isEmpty {
                        emptyState("No events yet — create a case and add an event.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recentEvents) { ev in
                                RecentEventRow(event: ev) {
                                    appState.selectedSection = .allCases
                                    appState.selectedCaseId = ev.caseId
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("Dashboard")
    }

    private var pinnedCases: [Case] {
        appState.cases.filter(\.pinned)
    }

    private var recentEvents: [Event] {
        appState.events
            .sorted { ($0.parsedStart ?? .distantPast) > ($1.parsedStart ?? .distantPast) }
            .prefix(8)
            .map { $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Pick a case from the sidebar, or use ⌘N to start a new one.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct CaseSummaryRow: View {
    @EnvironmentObject private var appState: AppState
    let aCase: Case
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                CaseStatusBadge(status: aCase.statusEnum, compact: true)
                Text(aCase.title.isEmpty ? "Untitled case" : aCase.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(appState.events.filter { $0.caseId == aCase.id }.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RecentEventRow: View {
    @EnvironmentObject private var appState: AppState
    let event: Event
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                ImportanceBadge(importance: event.importanceEnum, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? "Untitled event" : event.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let d = event.parsedStart {
                        Text(d.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let caseTitle = appState.cases.first(where: { $0.id == event.caseId })?.title {
                    Text(caseTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
