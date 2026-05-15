import SwiftUI

/// Type-ahead picker over the cached entity list. Looks like a text field
/// with an autocomplete dropdown below. Pure SwiftUI — no NSComboBox
/// wrapper, because the latter doesn't play nice with @Published updates.
struct ChannelCombobox: View {
    @EnvironmentObject var channels: ChannelService
    @Binding var query: String
    var onPick: (SlackEntity) -> Void

    @FocusState private var focused: Bool
    @State private var highlight: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Channel name, DM partner, or ID (C…/D…/U…)", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(pickHighlighted)

            if focused && !filtered.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filtered.prefix(20).enumerated()), id: \.element.id) { idx, entity in
                            row(for: entity, highlighted: idx == highlight)
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(entity); focused = false }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(.thickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.gray.opacity(0.25)))
            }
        }
        .onChange(of: query) { _, _ in highlight = 0 }
    }

    private var filtered: [SlackEntity] {
        channels.filtered(query)
    }

    private func pickHighlighted() {
        let matches = filtered
        guard !matches.isEmpty else { return }
        let idx = min(max(0, highlight), matches.count - 1)
        onPick(matches[idx])
        focused = false
    }

    @ViewBuilder
    private func row(for entity: SlackEntity, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: entity.kind))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name)
                    .font(AppFont.sans(13, weight: .medium))
                if let sub = entity.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(AppFont.sans(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(entity.id)
                .font(AppFont.mono(10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func iconName(for kind: SlackEntity.Kind) -> String {
        switch kind {
        case .channel: return "number"
        case .dm:      return "bubble.left"
        case .mpdm:    return "person.2"
        case .user:    return "person"
        }
    }
}
