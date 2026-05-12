import SwiftUI
import MasterClipperCore

/// Edit sheet for a SharedClipRow. Mirrors `EditClipSheet` for own clips but
/// submits to `SharedZoneEditor` instead of `IntentOutbox`. The edit becomes
/// a `SharedClipEdit` CKRecord in the share's zone; the Mac picks it up via
/// `SharedZoneSync` and applies through the same `apply(intent:)` path.
struct SharedEditSheet: View {
    let session: SharedShareSession
    let clip: SharedClipRow

    @EnvironmentObject private var appState: iOSAppState
    @Environment(\.dismiss) private var dismiss

    @State private var noteText: String = ""
    @State private var statusOverride: String?
    @State private var inFlight: Bool = false
    @State private var lastFeedback: String?

    init(session: SharedShareSession, clip: SharedClipRow) {
        self.session = session
        self.clip = clip
        _statusOverride = State(initialValue: clip.statusOverride)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !session.canEdit {
                    Section {
                        Text("This share is view-only.")
                            .foregroundStyle(.secondary)
                    }
                }

                statusSection
                postingsSection
                addNoteSection

                if let msg = lastFeedback {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .disabled(inFlight || !session.canEdit)
            .overlay(alignment: .center) {
                if inFlight { ProgressView().scaleEffect(1.4) }
            }
        }
    }

    private var statusSection: some View {
        Section("Status override") {
            Picker("Status", selection: $statusOverride) {
                Text("Auto (no override)").tag(String?.none)
                ForEach(ClipStatus.allCases, id: \.self) { s in
                    Label(s.label, systemImage: s.systemImage)
                        .tag(String?.some(s.rawValue))
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { await submitStatus() }
            } label: {
                Label("Apply status change", systemImage: "checkmark.circle")
            }
            .disabled(statusOverride == clip.statusOverride)
        }
    }

    private var postingsSection: some View {
        let postedSiteIds = Set(clip.postings.filter { $0.isPosted }.map(\.siteId))
        // We don't know the full Site list inside the share — work off the
        // postings the recipient has visibility into, plus the site IDs that
        // appear in clip.postings.
        return Section("Postings") {
            if clip.postings.isEmpty {
                Text("No postings on this clip yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clip.postings, id: \.self) { posting in
                    HStack {
                        Text("Site #\(posting.siteId)").font(.body.weight(.medium))
                        Spacer()
                        if posting.isPosted {
                            Button {
                                Task { await submitUnmarkPosted(siteId: posting.siteId) }
                            } label: {
                                Label("Posted", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                Task { await submitMarkPosted(siteId: posting.siteId) }
                            } label: {
                                Text("Mark posted").font(.callout.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Text("To mark posted on a site not yet attached, ask the share owner to add it on their Mac first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Suppress the unused-warning for postedSiteIds — we may use it
            // for a richer UI later.
            let _ = postedSiteIds
        }
    }

    private var addNoteSection: some View {
        Section("Add note") {
            TextEditor(text: $noteText)
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Type a note…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
            Button {
                Task { await submitAddNote() }
            } label: {
                Label("Save note", systemImage: "square.and.pencil")
            }
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Submitters

    private func submitStatus() async {
        await wrap("Status change queued") {
            await appState.sharedEditor.submitSetStatus(
                in: session, clipId: clip.id, status: statusOverride
            )
        }
    }

    private func submitAddNote() async {
        let body = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let ok = await wrap("Note queued") {
            await appState.sharedEditor.submitAddNote(
                in: session, clipId: clip.id,
                body: body, operatorName: appState.operatorName
            )
        }
        if ok { noteText = "" }
    }

    /// Mark-posted-by-siteId — the recipient sees a numeric siteId from the
    /// posting record, but our intent envelope wants a siteCode string. We
    /// don't have the full Site table in the share. Fall back to passing the
    /// numeric id as a string; macOS-side apply will look up by code OR
    /// numeric id (see SharedZoneSync's enrichment step).
    private func submitMarkPosted(siteId: Int64) async {
        await wrap("Marked posted on site #\(siteId)") {
            await appState.sharedEditor.submitMarkPosted(
                in: session, clipId: clip.id, siteCode: "id:\(siteId)"
            )
        }
    }

    private func submitUnmarkPosted(siteId: Int64) async {
        await wrap("Unmarked posted on site #\(siteId)") {
            await appState.sharedEditor.submitUnmarkPosted(
                in: session, clipId: clip.id, siteCode: "id:\(siteId)"
            )
        }
    }

    @discardableResult
    private func wrap(_ successMsg: String, _ work: () async -> Bool) async -> Bool {
        inFlight = true
        defer { inFlight = false }
        let ok = await work()
        if ok {
            lastFeedback = "✓ \(successMsg). Will sync once the Mac picks it up."
        } else if let err = appState.sharedEditor.lastError {
            lastFeedback = "⚠︎ \(err)"
        }
        return ok
    }
}
