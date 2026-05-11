import SwiftUI

/// One suspect card. Shows the scanned mugshot if `AssetResolver` has one;
/// otherwise renders a placeholder card with the suspect's id, name, sex
/// glyph, and a stylized silhouette.
struct SuspectCardView: View {
    let suspect: Suspect
    let knownLocation: Location?
    let highlighted: Bool

    @EnvironmentObject var assets: AssetResolver

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.94, green: 0.90, blue: 0.80))
                if let image = assets.suspectImage(id: suspect.id) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(4)
                        .padding(4)
                } else {
                    placeholderPortrait
                }
            }
            .frame(height: 90)
            .overlay(idTag, alignment: .topLeading)

            VStack(spacing: 1) {
                Text(suspect.name)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .lineLimit(1)
                Text(suspect.occupation)
                    .font(.system(size: 8, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(knownLocation?.code ?? "—")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(knownLocation == nil ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.black)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.99, green: 0.97, blue: 0.91))
                .shadow(color: .black.opacity(highlighted ? 0.7 : 0.4),
                        radius: highlighted ? 6 : 3, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(highlighted ? Color.orange : .black.opacity(0.35),
                        lineWidth: highlighted ? 2 : 0.5)
        )
    }

    private var idTag: some View {
        Text("#\(suspect.id)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.75)))
            .padding(4)
    }

    /// Period-styled silhouette + sex glyph fallback. Pure SwiftUI shapes so
    /// the card looks intentional rather than "broken asset".
    private var placeholderPortrait: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.78, green: 0.72, blue: 0.60),
                         Color(red: 0.62, green: 0.55, blue: 0.42)],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
            VStack(spacing: 0) {
                Circle().fill(.black.opacity(0.55)).frame(width: 26, height: 26)
                Capsule().fill(.black.opacity(0.55)).frame(width: 42, height: 22)
            }
            .offset(y: 6)
            Text(suspect.sex == .male ? "♂" : "♀")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 8).padding(.top, 8)
        }
    }
}
