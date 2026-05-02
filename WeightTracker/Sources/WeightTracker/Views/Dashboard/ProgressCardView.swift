import SwiftUI

struct ProgressCardView: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let accent: Color

    init(title: String, value: String, subtitle: String? = nil, icon: String, accent: Color) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
