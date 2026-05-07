import SwiftUI

struct EventEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var event: Event
    let isNew: Bool

    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date()
    @State private var importance: Importance = .medium
    @State private var selectedTags: Set<Int64> = []
    @State private var selectedPeople: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "New Event" : "Edit Event")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                Form {
                    Section("Basics") {
                        TextField("Title", text: $event.title)
                            .textFieldStyle(.roundedBorder)
                        DatePicker("When", selection: $startDate)
                        Toggle("Spans a range", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Through", selection: $endDate, in: startDate...)
                        }
                        Picker("Importance", selection: $importance) {
                            ForEach(Importance.allCases, id: \.self) { imp in
                                HStack {
                                    Circle().fill(imp.tint).frame(width: 8, height: 8)
                                    Text(imp.label)
                                }.tag(imp)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Description") {
                        TextEditor(text: $event.descriptionMarkdown)
                            .frame(minHeight: 140, maxHeight: 240)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                        Text("Markdown is rendered in the timeline view (bold, italic, links).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Source") {
                        TextField("Source URL or citation", text: $event.sourceURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    Section("Tags") {
                        if appState.tags.isEmpty {
                            Text("No tags yet — add one in **Tags** in the sidebar or Settings → Tags.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(appState.tags) { tag in
                                if let id = tag.rowId {
                                    Toggle(isOn: Binding(
                                        get: { selectedTags.contains(id) },
                                        set: { on in
                                            if on { selectedTags.insert(id) } else { selectedTags.remove(id) }
                                        }
                                    )) {
                                        TagChip(tag: tag, compact: true)
                                    }
                                    .toggleStyle(.button)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Section("People") {
                        let casePeople = appState.people.filter { $0.caseId == event.caseId }
                        if casePeople.isEmpty {
                            Text("No people on this case yet — add some on the **People** tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(casePeople) { p in
                            Toggle(isOn: Binding(
                                get: { selectedPeople.contains(p.id) },
                                set: { on in
                                    if on { selectedPeople.insert(p.id) } else { selectedPeople.remove(p.id) }
                                }
                            )) {
                                PersonRoleChip(
                                    person: p,
                                    colorHex: appState.settingsStore.roleColorHex(for: p.roleEnum)
                                )
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .padding(.horizontal, 20).padding(.top, 20)

                // Attachments — only enabled for events that have already been
                // saved (i.e. not the brand-new draft until first Save). For
                // a freshly-drafted event we surface a helpful placeholder
                // and let the user save first.
                AttachmentList(
                    parent: .event,
                    parentId: isNew ? nil : event.id
                )
                .padding(20)
            }

            Divider()
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        try? appState.deleteEvent(id: event.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        // Bound on every axis so the sheet can't grow past the window. The
        // ScrollView around the Form means the body content can request
        // unlimited height; without a maxHeight we'd hide the bottom button bar.
        .frame(minWidth: 580, idealWidth: 660, maxWidth: 880,
               minHeight: 540, idealHeight: 640, maxHeight: 820)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Hydrate state from the inbound event so DatePicker bindings work
            // off real Date values.
            if let parsed = event.parsedStart { startDate = parsed }
            if let end = event.parsedEnd { endDate = end; hasEndDate = true }
            importance = event.importanceEnum
            // For an existing event, prefill its tag and person selections.
            if !isNew {
                selectedTags = Set((appState.tagsByEvent[event.id] ?? []).compactMap(\.rowId))
                selectedPeople = Set((appState.peopleByEvent[event.id] ?? []).map(\.id))
            }
        }
    }

    private func save() {
        var saved = event
        saved.dateStart = ISO8601DateFormatter().string(from: startDate)
        saved.dateEnd = hasEndDate ? ISO8601DateFormatter().string(from: endDate) : nil
        saved.importanceEnum = importance
        do {
            if isNew {
                try DatabaseService.shared.insertEvent(saved)
            } else {
                try DatabaseService.shared.updateEvent(saved)
            }
            try DatabaseService.shared.setTags(Array(selectedTags), forEvent: saved.id)
            try DatabaseService.shared.setPeople(Array(selectedPeople), forEvent: saved.id)
            appState.reloadEvents()
            dismiss()
        } catch {
            NSLog("Timeliner: event save failed — \(error.localizedDescription)")
        }
    }
}

/// Lightweight wrap layout for tag toggles. Replaces the missing
/// `FlowLayout` symbol in iOS-only Layout snippets — implemented inline so
/// the editor stays self-contained.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > width {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > width {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: sz.width, height: sz.height))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
