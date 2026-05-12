import SwiftUI
import AppKit
import MasterClipperCore

/// Lives inside Settings → Sync. Shows every share zone we currently own
/// in CloudKit, with time remaining, recipient permission, and a revoke
/// button. Pull-to-refresh re-queries the private DB.
struct ActiveSharesView: View {
    @ObservedObject private var manager = ShareManager.shared
    @State private var showingCreateSheet = false
    @State private var confirmRevokeId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("External shares").font(.headline)
                Spacer()
                Button {
                    Task { await manager.refreshActiveShares() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(manager.isBusy)

                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Create share…", systemImage: "person.2.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Share a subset of your clips with someone who isn't you. They access via their own Apple ID and the MasterClipper iOS app — never your iCloud Drive.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let err = manager.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if manager.activeShares.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(manager.activeShares) { share in
                        shareRow(share)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingCreateSheet) {
            CreateShareSheet()
        }
        .task {
            await manager.refreshActiveShares()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No active shares").font(.headline)
            Text("Hit \"Create share…\" to bundle some clips for someone else to view or edit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private func shareRow(_ share: ShareSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(share.label?.nonEmpty ?? "Untitled share")
                    .font(.body.weight(.semibold))
                Spacer()
                Text(share.timeRemainingDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(share.isExpired || share.revoked ? .red : .secondary)
            }

            HStack(spacing: 16) {
                Label("\(share.clipCount) clips", systemImage: "film.stack")
                Label(share.permission.label, systemImage: share.permission == .readOnly ? "eye" : "pencil")
                Spacer()
                if let url = share.participationURL {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                Button(role: .destructive) {
                    confirmRevokeId = share.id
                } label: {
                    Label("Revoke", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Revoke this share?",
            isPresented: Binding(
                get: { confirmRevokeId == share.id },
                set: { if !$0 { confirmRevokeId = nil } }
            )
        ) {
            Button("Revoke now", role: .destructive) {
                Task { await manager.revokeShare(share.id) }
                confirmRevokeId = nil
            }
            Button("Cancel", role: .cancel) { confirmRevokeId = nil }
        } message: {
            Text("The recipient's iOS app will lose access on next refresh. This cannot be undone.")
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
