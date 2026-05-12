import SwiftUI
import MasterClipperCore

/// Compose-edit sheet for a single clip. Lets the iPhone user mark / unmark
/// per-site postings, change status (override), add a note, and toggle
/// posting exclusion. Every action funnels through `IntentOutbox`, which
/// writes a JSON envelope into iCloud; the Mac picks it up and applies it.
struct EditClipSheet: View {
    let clip: Clip
    @EnvironmentObject private var appState: iOSAppState
    @Environment(\.dismiss) private var dismiss

    @State private var noteText: String = ""
    @State private var statusOverride: String?
    @State private var postingExcluded: Bool
    @State private var exclusionReason: String
    @State private var exclusionNotes: String
    @State private var inFlight: Bool = false
    @State private var lastFeedback: String?

    init(clip: Clip) {
        self.clip = clip
        _statusOverride  = State(initialValue: clip.statusOverride)
        _postingExcluded = State(initialValue: clip.postingExcluded)
        _exclusionReason = State(initialValue: clip.exclusionReason)
        _exclusionNotes  = State(initialValue: clip.exclusionNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                postingsSection
                addNoteSection
                exclusionSection

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
            .disabled(inFlight)
            .overlay(alignment: .center) {
                if inFlight {
                    ProgressView().scaleEffect(1.4)
                }
            }
        }
    }

    // MARK: - Sections

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
        let inScopeSites = appState.sites.filter { $0.appliesTo(personaCode: clip.personaCode) }
        let postings = appState.postings(forClip: clip.id)
        let postedSiteIds = Set(postings.filter { $0.isPosted }.map(\.siteId))

        return Section("Postings") {
            if inScopeSites.isEmpty {
                Text("No sites scoped for persona \(clip.personaCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(inScopeSites) { site in
                    let isPosted = postedSiteIds.contains(site.id ?? -1)
                    HStack {
                        Text(site.code).font(.body.weight(.medium))
                        Text(site.displayName).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if isPosted {
                            Button {
                                Task { await submitUnmarkPosted(siteCode: site.code) }
                            } label: {
                                Label("Posted", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                Task { await submitMarkPosted(siteCode: site.code) }
                            } label: {
                                Text("Mark posted")
                                    .font(.callout.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
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

    private var exclusionSection: some View {
        Section("Exclude from posting") {
            Toggle("Excluded", isOn: $postingExcluded)
            if postingExcluded {
                TextField("Reason", text: $exclusionReason)
                TextField("Notes", text: $exclusionNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            Button {
                Task { await submitExclusion() }
            } label: {
                Label("Apply exclusion change", systemImage: "checkmark.circle")
            }
            .disabled(
                postingExcluded == clip.postingExcluded &&
                exclusionReason == clip.exclusionReason &&
                exclusionNotes == clip.exclusionNotes
            )
        }
    }

    // MARK: - Submitters

    private func submitMarkPosted(siteCode: String) async {
        await wrap("Marked posted on \(siteCode)") {
            await appState.outbox.submitMarkPosted(clipId: clip.id, siteCode: siteCode)
        }
    }

    private func submitUnmarkPosted(siteCode: String) async {
        await wrap("Unmarked posted on \(siteCode)") {
            await appState.outbox.submitUnmarkPosted(clipId: clip.id, siteCode: siteCode)
        }
    }

    private func submitAddNote() async {
        let body = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let ok = await wrap("Note queued") {
            await appState.outbox.submitAddNote(
                clipId: clip.id,
                body: body,
                operatorName: appState.operatorName
            )
        }
        if ok { noteText = "" }
    }

    private func submitStatus() async {
        await wrap("Status change queued") {
            await appState.outbox.submitSetStatus(clipId: clip.id, status: statusOverride)
        }
    }

    private func submitExclusion() async {
        await wrap("Exclusion change queued") {
            await appState.outbox.submitTogglePostingExcluded(
                clipId: clip.id,
                excluded: postingExcluded,
                reason: exclusionReason,
                notes: exclusionNotes
            )
        }
    }

    @discardableResult
    private func wrap(_ successMsg: String, _ work: () async -> Bool) async -> Bool {
        inFlight = true
        defer { inFlight = false }
        let ok = await work()
        if ok {
            lastFeedback = "✓ \(successMsg). Will sync once your Mac picks it up."
        } else if let err = appState.outbox.lastError {
            lastFeedback = "⚠︎ \(err)"
        }
        return ok
    }
}
