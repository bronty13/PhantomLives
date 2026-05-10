import SwiftUI

/// Object detail — the sheet that opens when a row is clicked. Renders
/// every field on the type with an editor appropriate for its kind, saves
/// on dismiss. Phase 2 starting point — the full design's two-pane detail
/// (fields on the left, linked-from rail on the right) lands later.
struct ObjectDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let recordId: String
    var onChange: () -> Void = {}

    @State private var record: ObjectRecord?
    @State private var fieldsBuffer: [String: Any] = [:]
    @State private var error: String?

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
        .frame(minWidth: 560, minHeight: 520)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(orderedFields(for: type), id: \.id) { field in
                        fieldEditor(field: field)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))

            if let error {
                Divider()
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
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
        case .text, .url, .email, .link:
            TextField(field.name, text: stringBinding(field.key))
                .textFieldStyle(.roundedBorder)
        case .longText:
            TextEditor(text: stringBinding(field.key))
                .frame(minHeight: 80, maxHeight: 200)
                .font(.body)
                .scrollContentBackground(.hidden)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
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
            // Phase 2 starter — actual picker lands when AttachmentService
            // is wired. For now we show what's in the blob.
            if let sha = fieldsBuffer[field.key] as? String, !sha.isEmpty {
                Label(sha.prefix(12) + "…", systemImage: "paperclip")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("No attachment").foregroundStyle(.tertiary)
            }
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
