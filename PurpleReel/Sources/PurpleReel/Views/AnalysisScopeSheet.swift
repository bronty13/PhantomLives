import SwiftUI

/// "Analysis Scope" dialog (Kyno-parity, Image #90). Pops when the
/// user picks right-click → Pre-analyze; lets them choose which work
/// to redo. Defaults match Kyno's: Technical metadata + Thumbnails
/// on, Key frames off (and disabled in PurpleReel until extraction
/// lands).
struct AnalysisScopeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var scope: AnalysisScope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Technical metadata",
                        isOn: bindingFor(.technicalMetadata))
                    .help("Re-runs the AVAsset probe (duration / codec / dims / fps / audio codec / recorded-at / VFR) and writes refreshed values back to the catalog.")
                Toggle("Thumbnails",
                        isOn: bindingFor(.thumbnails))
                    .help("Purges the asset's thumbnail-strip cache and forces regeneration on the next render. Useful after fixing source files out-of-band.")
                Toggle("Key frames", isOn: .constant(false))
                    .disabled(true)
                    .help("Scene-change keyframe extraction is reserved for a future build — currently the strip uses evenly-distributed frames.")
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 420, height: 240)
    }

    private var header: some View {
        HStack {
            Text("Analysis Scope").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func bindingFor(_ option: AnalysisScope) -> Binding<Bool> {
        Binding<Bool>(
            get: { scope.contains(option) },
            set: { isOn in
                if isOn { scope.insert(option) }
                else    { scope.remove(option) }
            }
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Start") {
                appState.preAnalyzeSelected(scope: scope)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(scope.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
