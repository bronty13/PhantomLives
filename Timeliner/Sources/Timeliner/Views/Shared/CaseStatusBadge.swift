import SwiftUI

struct CaseStatusBadge: View {
    let status: CaseStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(compact ? .caption2 : .caption)
            if !compact {
                Text(status.label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(status.tint.opacity(0.15))
        )
    }
}
