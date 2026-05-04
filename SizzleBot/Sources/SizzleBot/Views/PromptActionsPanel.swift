import SwiftUI

/// Renders below an assistant message from a vision-enabled bot. Surfaces
/// the parsed paragraph + style variants as one row each, with a `Use ▾`
/// menu that copies or sends the prompt to a Stable-Diffusion app.
struct PromptActionsPanel: View {
    let paragraph: String
    let variants: [String]

    @State private var feedback: String?
    @State private var clearTask: Task<Void, Never>?

    private struct Option: Identifiable {
        let id = UUID()
        let label: String
        let prompt: String
        let isPlain: Bool
    }

    private var options: [Option] {
        var result: [Option] = [
            Option(
                label: "Plain (no style)",
                prompt: PromptExporter.composePrompt(paragraph: paragraph, variant: nil),
                isPlain: true
            )
        ]
        for v in variants {
            result.append(
                Option(
                    label: v,
                    prompt: PromptExporter.composePrompt(paragraph: paragraph, variant: v),
                    isPlain: false
                )
            )
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generate an image with this prompt:")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(options) { opt in
                    OptionRow(option: opt) { action in
                        perform(action, on: opt)
                    }
                }
            }

            if let f = feedback {
                Text(f)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Tip: neither app supports prompt prefill via URL. We copy the prompt and bring the app to front — paste with ⌘V.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 520, alignment: .leading)
    }

    private enum Action {
        case copy
        case send(PromptExporter.Target)
    }

    private func perform(_ action: Action, on opt: Option) {
        switch action {
        case .copy:
            PromptExporter.copyToClipboard(opt.prompt)
            announce("Copied \"\(opt.label)\" prompt to clipboard.")
        case .send(let target):
            let result = PromptExporter.send(prompt: opt.prompt, to: target)
            switch result {
            case .launched(let t):
                announce("\(t.displayName) launched — paste with ⌘V (\"\(opt.label)\" copied).")
            case .appNotFound(let t):
                announce("\(t.displayName) not found in /Applications. Prompt copied — open the app manually and paste.")
            }
        }
    }

    private func announce(_ message: String) {
        clearTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { feedback = message }
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) { feedback = nil }
            }
        }
    }

    // MARK: Row

    private struct OptionRow: View {
        let option: Option
        let action: (Action) -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: option.isPlain ? "doc.plaintext" : "paintpalette")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(option.label)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Menu {
                    Button {
                        action(.copy)
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        action(.send(.drawThings))
                    } label: {
                        Label("Send to Draw Things", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        action(.send(.diffusionBee))
                    } label: {
                        Label("Send to DiffusionBee", systemImage: "arrow.up.right.square")
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Use").font(.caption.weight(.medium))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(option.isPlain ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.secondary.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
