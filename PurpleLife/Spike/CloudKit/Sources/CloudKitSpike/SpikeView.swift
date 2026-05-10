import SwiftUI

struct SpikeView: View {
    @ObservedObject var viewModel: SpikeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CloudKit `encryptedValues` round-trip")
                    .font(.title2).bold()
                Text("Container: \(SpikeViewModel.containerID)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.runSpike() }
                } label: {
                    Label("Run round-trip", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning)

                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if let result = viewModel.result {
                    Label(
                        result.passed ? "PASS" : "FAIL",
                        systemImage: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill"
                    )
                    .foregroundStyle(result.passed ? .green : .red)
                    .font(.headline)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.log) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.timestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    if viewModel.log.isEmpty {
                        Text("Click \"Run round-trip\" to begin. The spike saves a record with an encrypted JSON blob, fetches it back, and verifies the bytes match.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }
}
