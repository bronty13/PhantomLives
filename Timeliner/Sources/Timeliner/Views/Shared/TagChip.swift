import SwiftUI

struct TagChip: View {
    let tag: Tag
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .gray)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
            Text(tag.name)
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Capsule().fill((Color(hex: tag.colorHex) ?? .gray).opacity(0.18))
        )
        .overlay(
            Capsule().stroke((Color(hex: tag.colorHex) ?? .gray).opacity(0.4), lineWidth: 0.5)
        )
        .foregroundStyle(.primary)
    }
}
