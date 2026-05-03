import SwiftUI

struct SetupView: View {
    @ObservedObject var setup: OllamaSetup

    var body: some View {
        VStack(spacing: 32) {
            Text("👻")
                .font(.system(size: 64))

            Text("SizzleBot")
                .font(.largeTitle.bold())

            Group {
                switch setup.state {
                case .idle, .checkingInstall:
                    startingRow(icon: "magnifyingglass", message: "Looking for Ollama…")

                case .notInstalled:
                    notInstalledView

                case .startingServer:
                    startingRow(icon: "server.rack", message: "Starting Ollama server…")

                case .pullingModel(let progress):
                    pullingView(progress: progress)

                case .ready:
                    startingRow(icon: "checkmark.circle.fill", message: "Ready!", tint: .green)

                case .failed(let msg):
                    failedView(message: msg)
                }
            }
            .frame(width: 360)
        }
        .frame(width: 480, height: 360)
        .background(.background)
    }

    private func startingRow(icon: String, message: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            if tint == .secondary {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).foregroundStyle(tint).font(.title3)
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Ollama is not installed")
                .font(.headline)

            Text("SizzleBot needs Ollama to run local AI models on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            HStack(spacing: 12) {
                Button("Install via Homebrew") {
                    setup.installBrew()
                }
                .buttonStyle(.borderedProminent)

                Link("Get Ollama", destination: URL(string: "https://ollama.com")!)
                    .buttonStyle(.bordered)
            }

            Button("Retry") { Task { await setup.run() } }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    private func pullingView(progress: Double) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(setup.statusMessage).foregroundStyle(.secondary)
            }
            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("This only happens once. Grab a coffee ☕")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            Text("Setup failed")
                .font(.headline)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal)

            Button("Try Again") { Task { await setup.run() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
