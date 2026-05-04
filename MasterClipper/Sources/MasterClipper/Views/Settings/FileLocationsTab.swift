import SwiftUI

/// File-location defaults used by the path-helper buttons in the clip editor
/// and the one-time backfill. Patterns accept `{date}` and `{title}`
/// placeholders. The backfill runs once at first launch (tracked by
/// `pathBackfillV1Done`); the "Run backfill now" button forces a re-run
/// against the current settings.
struct FileLocationsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var lastResult: PathDefaultsService.BackfillResult?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Production folder") {
                TextField("Base path", text: Binding(
                    get: { appState.settings.defaultProductionBase },
                    set: { var s = appState.settings; s.defaultProductionBase = $0; appState.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("Subfolder pattern", text: Binding(
                    get: { appState.settings.defaultProductionPattern },
                    set: { var s = appState.settings; s.defaultProductionPattern = $0; appState.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Resolved example: \(productionPreview)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Section("FCP project folder") {
                TextField("Base path", text: Binding(
                    get: { appState.settings.defaultFCPBase },
                    set: { var s = appState.settings; s.defaultFCPBase = $0; appState.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("Subfolder pattern", text: Binding(
                    get: { appState.settings.defaultFCPPattern },
                    set: { var s = appState.settings; s.defaultFCPPattern = $0; appState.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Resolved example: \(fcpPreview)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Section("File handling") {
                HStack {
                    Text("Large-file threshold")
                        .frame(width: 220, alignment: .leading)
                    TextField("MB", value: Binding(
                        get: { appState.settings.largeFileThresholdMB },
                        set: { var s = appState.settings; s.largeFileThresholdMB = max(1, $0); appState.settings = s }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    Text("MB").foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Main MP4s above this size are flagged in the file audit and will be auto-reduced to a `<Title>_reduced.mp4` companion when Phase 2 file ops run.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Text("Frames to capture per clip")
                        .frame(width: 220, alignment: .leading)
                    Stepper(value: Binding(
                        get: { appState.settings.numFramesToCapture },
                        set: { var s = appState.settings; s.numFramesToCapture = max(1, $0); appState.settings = s }
                    ), in: 1...60) {
                        Text("\(appState.settings.numFramesToCapture)")
                            .font(.body.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                    Spacer()
                }
                Text("First frame is taken from the 1–9 s window (catches the title card); the remainder are randomly spaced through the rest of the clip.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Backfill") {
                Text("Sets the path columns for every active clip in Production status whose path is currently empty. Idempotent — re-running with nothing to fill is a no-op.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Run backfill now") { runBackfill() }
                        .buttonStyle(.borderedProminent)
                    if let r = lastResult {
                        Text("Production: +\(r.productionFilled) · FCP: +\(r.fcpFilled) · skipped: \(r.skipped) · failed: \(r.failed)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = error {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Section("Placeholders") {
                Text("`{date}` is the clip's content date (falls back to go-live date). `{title}` is the clip title with `/`, `\\`, and `:` replaced with `-`. Tilde (`~`) in the base path is expanded to the user's home directory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Resolved previews

    /// A representative-looking sample path so the user can see what's
    /// actually going to be written. Uses today's date and a placeholder title.
    private var productionPreview: String {
        let today = Self.todayISO()
        let sample = sampleClip(date: today, title: "Sample Title")
        return PathDefaultsService.productionPath(for: sample, settings: appState.settings)
            ?? "(set the base path and pattern to see a preview)"
    }

    private var fcpPreview: String {
        let today = Self.todayISO()
        let sample = sampleClip(date: today, title: "Sample Title")
        return PathDefaultsService.fcpPath(for: sample, settings: appState.settings)
            ?? "(set the base path and pattern to see a preview)"
    }

    private func sampleClip(date: String, title: String) -> Clip {
        Clip(
            id: "sample",
            externalClipId: nil, trackingTag: nil,
            personaCode: appState.settings.defaultPersonaCode,
            title: title,
            descriptionRaw: "", descriptionRefined: "",
            keywords: "", performers: "",
            clipFilename: nil, thumbnailFilename: nil, previewFilename: nil,
            lengthSeconds: nil, priceCents: nil, salesCount: 0, incomeCents: 0,
            contentDate: date, goLiveDate: date,
            fcpProjectFolder: nil, productionFolder: nil,
            status: ClipStatus.new.rawValue, archived: false, notes: "",
            transcript: "",
            mp4Md5: "", mp4Sha1: "", mp4Sha256: "", mp4SizeBytes: nil,
            reducedMd5: "", reducedSha1: "", reducedSha256: "", reducedSizeBytes: nil,
            hashesComputedAt: "",
            createdAt: "", updatedAt: ""
        )
    }

    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: - Backfill action

    private func runBackfill() {
        let result = PathDefaultsService.backfill(appState: appState)
        lastResult = result
        error = nil
    }
}
