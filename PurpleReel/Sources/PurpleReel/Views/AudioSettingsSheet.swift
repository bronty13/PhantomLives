import SwiftUI

/// Audio-channel settings sheet. Edits the `AudioEncoding` of an
/// `.reencode(...)` audio channel; if the channel is `.copy` or
/// `.disabled` the sheet shows a placeholder explaining why nothing
/// is editable.
struct AudioSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var channel: AudioChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    bodyContent
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 320)
    }

    private var header: some View {
        HStack {
            Text("Audio Settings").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch channel {
        case .copy:
            Text("Audio is set to Copy — no re-encoding parameters apply. Switch the Audio channel to Re-Encode in the main Convert dialog to edit codec, sample rate, and bitrate.")
                .foregroundStyle(.secondary)
        case .disabled:
            Text("Audio is disabled — output will have no audio track. Switch the Audio channel to Copy or Re-Encode in the main Convert dialog to restore.")
                .foregroundStyle(.secondary)
        case .reencode(let encoding):
            reencodeForm(encoding: encoding)
        }
    }

    @ViewBuilder
    private func reencodeForm(encoding: AudioEncoding) -> some View {
        let codecBinding = Binding<AudioCodec>(
            get: { encoding.codec },
            set: { newCodec in
                var next = encoding
                next.codec = newCodec
                channel = .reencode(next)
            }
        )
        let sampleRateBinding = Binding<Int>(
            get: { encoding.sampleRate },
            set: { newRate in
                var next = encoding
                next.sampleRate = newRate
                channel = .reencode(next)
            }
        )
        let bitrateBinding = Binding<Int>(
            get: { encoding.bitrateKbps },
            set: { newBitrate in
                var next = encoding
                next.bitrateKbps = newBitrate
                channel = .reencode(next)
            }
        )

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Codec:").foregroundStyle(.secondary)
                Picker("", selection: codecBinding) {
                    ForEach(AudioCodec.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240, alignment: .leading)
            }
            GridRow {
                Text("Sample rate:").foregroundStyle(.secondary)
                Picker("", selection: sampleRateBinding) {
                    Text("44.1 kHz").tag(44_100)
                    Text("48 kHz").tag(48_000)
                    Text("96 kHz").tag(96_000)
                }
                .labelsHidden()
                .frame(maxWidth: 160, alignment: .leading)
            }
            GridRow {
                Text("Bitrate:").foregroundStyle(.secondary)
                HStack {
                    Picker("", selection: bitrateBinding) {
                        Text("128 kbit/s").tag(128)
                        Text("192 kbit/s").tag(192)
                        Text("256 kbit/s").tag(256)
                        Text("320 kbit/s").tag(320)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160, alignment: .leading)
                    if encoding.codec == .pcm16
                       || encoding.codec == .pcm24
                       || encoding.codec == .pcm32 {
                        Text("(ignored for PCM — uncompressed)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
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
