import SwiftUI

/// Object detail — the sheet that opens when a row is clicked. Two-
/// pane layout matching the prototype's `ScreenDetail` (`Design/
/// purplelife/project/screens-dark.jsx`):
///
/// - **Main**: hero block (large icon + record title) followed by
///   each field with a kind-appropriate editor, saved on dismiss.
/// - **Right rail (320 px)**: "Linked from" — every record across
///   every type whose `.link` fields point at this record. Grouped by
///   type, click navigates by setting `appState.openRecordRequest`.
struct ObjectDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let recordId: String
    var onChange: () -> Void = {}

    @State private var record: ObjectRecord?
    @State private var fieldsBuffer: [String: Any] = [:]
    @State private var error: String?
    @State private var richTextSizeError: String?

    var body: some View {
        Group {
            if let record, let type = appState.schema.type(id: record.typeId) {
                editor(record: record, type: type)
            } else if let error {
                Text("Couldn't load record: \(error)")
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView().controlSize(.small).padding()
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .onAppear { load() }
    }

    private func editor(record: ObjectRecord, type: ObjectType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: type.systemImage)
                    .foregroundStyle(Color(hex: type.colorHex) ?? .accentColor)
                Text(type.name).font(.title2).bold()
                Spacer()
                Button("Done") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()

            HStack(spacing: 0) {
                mainPane(record: record, type: type)
                    .frame(maxWidth: .infinity)
                Divider()
                inspectorRail(record: record, type: type)
                    .frame(width: 320)
            }
            .frame(maxHeight: .infinity)

            if let error {
                Divider()
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
    }

    // MARK: - Main pane

    private func mainPane(record: ObjectRecord, type: ObjectType) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(record: record, type: type)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(orderedFields(for: type), id: \.id) { field in
                        fieldEditor(field: field)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
    }

    private func hero(record: ObjectRecord, type: ObjectType) -> some View {
        let tone = Color(hex: type.colorHex) ?? .accentColor
        let title = FieldDisplay.title(of: record, in: type)
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(tone.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: type.systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(tone)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(type.name)
                    .font(.caption2).fontWeight(.semibold).tracking(0.5)
                    .textCase(.uppercase).foregroundStyle(.tertiary)
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(title.isEmpty ? Color.secondary : Color.primary)
            }
            Spacer()
        }
    }

    // MARK: - Inspector rail

    private func inspectorRail(record: ObjectRecord, type: ObjectType) -> some View {
        let inbound = (try? ObjectEngine.recordsLinkingTo(recordId: record.id, schema: appState.schema)) ?? []
        let groupedByType = Dictionary(grouping: inbound, by: { $0.type.id })
        let typeOrder = inbound.map(\.type.id).reduce(into: [String]()) { acc, id in
            if !acc.contains(id) { acc.append(id) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Linked from")
                    .font(.caption2).fontWeight(.semibold).tracking(0.5)
                    .textCase(.uppercase).foregroundStyle(.tertiary)
                if inbound.isEmpty {
                    Text("Nothing yet links here.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(typeOrder, id: \.self) { typeId in
                        if let group = groupedByType[typeId], let groupType = group.first?.type {
                            inboundGroup(type: groupType, items: group)
                        }
                    }
                }
                Spacer(minLength: 0)
                metadata(record: record)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sidebarOpaque.opacity(0.4))
    }

    private func inboundGroup(type: ObjectType, items: [(record: ObjectRecord, type: ObjectType)]) -> some View {
        let tone = Color(hex: type.colorHex) ?? .accentColor
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .foregroundStyle(tone)
                    .imageScale(.small)
                Text(type.pluralName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ForEach(items, id: \.record.id) { item in
                Button {
                    appState.openRecordRequest = item.record.id
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tone.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(FieldDisplay.title(of: item.record, in: item.type))
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Tiny created/updated stamps at the bottom of the rail. The
    /// prototype shows a richer history timeline; PurpleLife doesn't
    /// keep a per-mutation log yet, so this is what we have to show
    /// without adding new persistence.
    private func metadata(record: ObjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 4)
            Text("Created \(humanize(record.createdAt))")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("Updated \(humanize(record.updatedAt))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func humanize(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    private func orderedFields(for type: ObjectType) -> [FieldDef] {
        guard let primaryKey = type.primaryFieldKey else { return type.fields }
        var ordered = type.fields
        if let idx = ordered.firstIndex(where: { $0.key == primaryKey }), idx > 0 {
            ordered.insert(ordered.remove(at: idx), at: 0)
        }
        return ordered
    }

    @ViewBuilder
    private func fieldEditor(field: FieldDef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: field.kind.systemImage)
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                Text(field.name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                if field.required {
                    Text("required").font(.caption2).foregroundStyle(.red.opacity(0.8))
                }
            }
            editorBody(for: field)
        }
    }

    @ViewBuilder
    private func editorBody(for field: FieldDef) -> some View {
        switch field.kind {
        case .text, .url, .email:
            TextField(field.name, text: stringBinding(field.key))
                .textFieldStyle(.roundedBorder)
        case .link:
            LinkFieldEditor(value: stringBinding(field.key))
        case .longText:
            TextEditor(text: stringBinding(field.key))
                .frame(minHeight: 80, maxHeight: 200)
                .font(.body)
                .scrollContentBackground(.hidden)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        case .richText:
            VStack(alignment: .leading, spacing: 4) {
                RichTextField(
                    fieldKey: field.key,
                    fieldsBuffer: $fieldsBuffer,
                    sizeError: $richTextSizeError
                )
                if let err = richTextSizeError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        case .number:
            TextField(field.name, value: doubleBinding(field.key), format: .number)
                .textFieldStyle(.roundedBorder)
        case .date:
            DatePicker("", selection: dateBinding(field.key, includeTime: false), displayedComponents: .date)
                .labelsHidden()
        case .dateTime:
            DatePicker("", selection: dateBinding(field.key, includeTime: true),
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        case .boolean:
            Toggle("", isOn: boolBinding(field.key)).labelsHidden()
        case .select:
            Picker("", selection: stringBinding(field.key)) {
                Text("—").tag("")
                ForEach(field.options) { opt in
                    Text(opt.name).tag(opt.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        case .multiSelect:
            multiSelectEditor(field: field)
        case .rating:
            ratingEditor(field: field)
        case .attachment:
            AttachmentFieldEditor(
                value: stringBinding(field.key),
                parentObjectId: recordId,
                fieldKey: field.key
            )
        }
    }

    private func multiSelectEditor(field: FieldDef) -> some View {
        let current = (fieldsBuffer[field.key] as? [String]) ?? []
        return WrappingHStack(items: field.options) { opt in
            let isOn = current.contains(opt.name)
            let chipColor: Color = opt.colorHex.flatMap(Color.init(hex:)) ?? .secondary
            Button {
                var next = current
                if isOn { next.removeAll { $0 == opt.name } }
                else    { next.append(opt.name) }
                fieldsBuffer[field.key] = next
            } label: {
                Text(opt.name)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isOn ? chipColor.opacity(0.25) : Color.secondary.opacity(0.08))
                    .foregroundStyle(isOn ? chipColor : Color.secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func ratingEditor(field: FieldDef) -> some View {
        let current = (fieldsBuffer[field.key] as? Int) ?? Int((fieldsBuffer[field.key] as? Double) ?? 0)
        return HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    fieldsBuffer[field.key] = (current == i) ? 0 : i
                } label: {
                    Image(systemName: i <= current ? "star.fill" : "star")
                        .foregroundStyle(i <= current ? Color.yellow : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bindings

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { (fieldsBuffer[key] as? String) ?? "" },
            set: { fieldsBuffer[key] = $0 }
        )
    }

    private func doubleBinding(_ key: String) -> Binding<Double?> {
        Binding(
            get: { fieldsBuffer[key] as? Double },
            set: { fieldsBuffer[key] = $0 }
        )
    }

    /// Read-write binding for the `plain` mirror of a richText field's
    /// JSON dictionary. Slice B1 uses this against a plain `TextEditor`;
    /// slice B2 replaces the editor with the AppKit `RichTextEditor` host
    /// and binds to the full `RichTextValue`.
    private func richTextPlainBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                guard let dict = fieldsBuffer[key] as? [String: Any] else { return "" }
                return (dict["plain"] as? String) ?? ""
            },
            set: {
                var dict = (fieldsBuffer[key] as? [String: Any]) ?? [:]
                dict["plain"] = $0
                // Until the AppKit editor lands in B2, the RTF blob stays
                // whatever it was; the plain-mirror text is the only
                // user-edit surface. Leaving `rtf` unset is fine — the
                // storage shape treats missing `rtf` as empty.
                fieldsBuffer[key] = dict
            }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { (fieldsBuffer[key] as? Bool) ?? false },
            set: { fieldsBuffer[key] = $0 }
        )
    }

    private func dateBinding(_ key: String, includeTime: Bool) -> Binding<Date> {
        Binding(
            get: {
                if let s = fieldsBuffer[key] as? String,
                   let d = ISO8601DateFormatter().date(from: s) {
                    return d
                }
                return Date()
            },
            set: { fieldsBuffer[key] = ISO8601DateFormatter().string(from: $0) }
        )
    }

    // MARK: - Actions

    private func load() {
        do {
            guard let r = try appState.database.fetchObject(id: recordId) else {
                error = "Record not found"
                return
            }
            record = r
            fieldsBuffer = r.fields()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveAndDismiss() {
        guard var r = record else { dismiss(); return }
        do {
            r = try ObjectEngine.update(r, fields: fieldsBuffer)
            record = r
            onChange()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Tiny wrap-on-overflow HStack — used by the multi-select chip cluster.
private struct WrappingHStack<T: Identifiable, Content: View>: View {
    let items: [T]
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}

/// Minimal flow layout — wraps children onto multiple lines like CSS
/// `flex-wrap: wrap`. Phase 2 starter; SwiftUI's stock `Layout`
/// protocol gives us exactly the behavior we need with ~30 lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: maxRowWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
