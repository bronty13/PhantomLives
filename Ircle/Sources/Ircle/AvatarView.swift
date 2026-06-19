import SwiftUI

/// A single user "face": the assigned image if one exists, otherwise a
/// generated monogram (deterministic color + initials from the nick).
struct AvatarView: View {
    @EnvironmentObject var faces: FacesStore
    let nick: String
    var size: CGFloat = 48

    var body: some View {
        // Re-read on assignment changes so a freshly-set image appears live.
        let _ = faces.assignments
        Group {
            if let img = faces.image(for: nick) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hue: FaceGraphics.hue(for: nick), saturation: 0.45, brightness: 0.72)
                    Text(FaceGraphics.initials(for: nick))
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        )
    }
}
