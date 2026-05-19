import SwiftUI

/// File & Container settings sheet (Kyno's "File format → Settings…"
/// flyout, Image #85). Edits the `ContainerSettings` block of a
/// `TranscodeOptions` value. Wired as a binding so the parent
/// ConvertSheet's editableOptions stays the single source of truth.
struct ContainerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: ContainerSettings
    @Binding var timecodeSource: TimecodeSource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fileSettings
                    Divider()
                    metadataSettings
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 360)
    }

    private var header: some View {
        HStack {
            Text("File & Container Settings").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var fileSettings: some View {
        Text("File Settings").font(.title3.weight(.semibold))
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Streamability:").foregroundStyle(.secondary)
                Toggle("Create streamable container file",
                        isOn: $settings.streamable)
            }
            GridRow {
                Text("File timestamps:").foregroundStyle(.secondary)
                Toggle("Keep creation and modification timestamps of original file",
                        isOn: $settings.keepSourceTimestamps)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var metadataSettings: some View {
        Text("Metadata Settings").font(.title3.weight(.semibold))
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Timecode:").foregroundStyle(.secondary)
                Picker("", selection: $timecodeSource) {
                    Text("From Source Timecode (if available)")
                        .tag(TimecodeSource.fromSourceIfAvailable)
                    Text("Zero-Based").tag(TimecodeSource.zeroBased)
                    Text("Custom").tag(TimecodeSource.custom)
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
            }
            GridRow {
                Text("XMP:").foregroundStyle(.secondary)
                Toggle("Add XMP metadata to the container",
                        isOn: $settings.embedXMPMetadata)
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
