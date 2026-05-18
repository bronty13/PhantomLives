import SwiftUI

/// First-launch sheet asking new users if they're coming from Kyno
/// and want PurpleReel to adopt Kyno's keyboard / sort / label
/// conventions. Shown once (gated on
/// `KynoCompatibility.promptShownKey`); user can flip the same
/// preset later via Settings → General.
///
/// Design intent: a clear, non-pushy onboarding moment. We don't
/// auto-enable Kyno mode — the user has to opt in. The default
/// "Use PurpleReel defaults" path keeps the app's native behavior.
struct ComingFromKynoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming from Kyno?")
                        .font(.title2.weight(.semibold))
                    Text("Pick the keyboard layout and defaults you'd like.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Kyno compatibility mode will:")
                    .font(.subheadline.weight(.medium))
                BulletPoint("Use J/L for 5-second jumps (Kyno default) instead of multi-rate shuttle.")
                BulletPoint("Use 'Thumbnail' instead of 'Grid' for the first view mode.")
                BulletPoint("Sort filenames numerically (`clip2` before `clip10`).")
                BulletPoint("Stop auto-enabling drilldown on camera-card mounts.")
                Text("Plus PurpleReel adds Kyno-familiar shortcuts regardless of your choice: X mutes audio, ⌘⇧D toggles drilldown, ⌘U exports the I/O subclip, ⌃⌥E toggles zebra, ⌃⌥W toggles widescreen matte, ⌥⇧O opens with the default app, ⌘⌥M focuses the metadata input, and ⌘←/⌘→ step between clips in Detail view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 4)

            HStack {
                Button("Use PurpleReel Defaults") {
                    KynoCompatibility.restore()
                    UserDefaults.standard.set(true,
                                                forKey: KynoCompatibility.promptShownKey)
                    dismiss()
                }
                Spacer()
                Button("Enable Kyno Compatibility") {
                    KynoCompatibility.apply()
                    UserDefaults.standard.set(true,
                                                forKey: KynoCompatibility.promptShownKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            Text("You can flip this anytime in Settings → General → Kyno Compatibility.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct BulletPoint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.callout)
            Spacer()
        }
    }
}
