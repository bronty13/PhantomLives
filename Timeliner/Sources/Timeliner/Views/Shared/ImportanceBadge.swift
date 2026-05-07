import SwiftUI

/// Four-pip importance indicator. Filled pips reflect `Importance.filledPips`;
/// the rest are drawn as faint outlines so the visual width is constant.
struct ImportanceBadge: View {
    let importance: Importance
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < importance.filledPips ? importance.tint : importance.tint.opacity(0.18))
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
            }
        }
        .help(importance.label)
    }
}

struct PersonRoleChip: View {
    let person: Person
    var colorHex: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: person.roleEnum.systemImage)
                .font(.caption2)
            Text(person.name.isEmpty ? person.roleEnum.label : person.name)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((Color(hex: colorHex) ?? .gray).opacity(0.18))
        )
        .overlay(
            Capsule().stroke((Color(hex: colorHex) ?? .gray).opacity(0.4), lineWidth: 0.5)
        )
    }
}
