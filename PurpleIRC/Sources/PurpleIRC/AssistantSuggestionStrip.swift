import SwiftUI

/// Above-the-input-bar UI for the local-LLM assistant. Only renders when
/// the buffer is engaged (`/assist` toggled on). Three states:
/// - generating — spinner + persona name
/// - ready      — draft text + Send / Edit / Regenerate / Dismiss
/// - failed     — inline error + Retry / Dismiss
///
/// Idle state renders nothing so the strip doesn't take up vertical space
/// on every query buffer once the user has the assistant enabled globally.
struct AssistantSuggestionStrip: View {
    let bufferIndex: Int
    /// Drop the suggestion text into the input field for editing. The
    /// caller (BufferView) owns the input @State so we hand it back via
    /// callback instead of binding into a far-away source of truth.
    let onAccept: (String) -> Void
    /// Send the suggestion as-is, bypassing the input field. Calls the
    /// same outbound path as a manual send.
    let onSendDirect: (String) -> Void

    @EnvironmentObject var model: ChatModel

    private var buffer: Buffer? {
        let bs = model.buffers
        guard bufferIndex < bs.count else { return nil }
        return bs[bufferIndex]
    }

    private var connectionID: UUID? { model.activeConnection?.id }

    private var state: AssistantState {
        guard let buf = buffer else { return .idle }
        return model.assistant.stateForBuffer[buf.id] ?? .idle
    }

    private var isEngaged: Bool {
        guard let buf = buffer else { return false }
        return model.assistant.isEngaged(bufferID: buf.id)
    }

    var body: some View {
        // Hide entirely when not engaged — keeps the input bar quiet
        // for buffers the user isn't actively assisting.
        if isEngaged {
            VStack(spacing: 0) {
                Divider()
                content
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleRow
        case .generating:
            generatingRow
        case .ready(let suggestion):
            readyRow(suggestion)
        case .failed(let message):
            failedRow(message)
        }
    }

    private var idleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            let persona = buffer.flatMap { model.assistant.activePersona(bufferID: $0.id) }
            Text("Assistant ready — \(persona?.name ?? "no persona") · waiting for next message")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Suggest now") { regenerate() }
                .controlSize(.small)
            Button { disengage() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Disengage assistant")
        }
    }

    private var generatingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Drafting reply…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
        }
    }

    private func readyRow(_ s: AssistantSuggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.text)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Suggestion · \(s.personaName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Button("Send") { onSendDirect(s.text); dismiss() }
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .help("Send as-is — ⌘⏎")
                    Button("Edit") { onAccept(s.text); dismiss() }
                        .controlSize(.small)
                        .help("Load into the input field for editing")
                }
                HStack(spacing: 4) {
                    Button { regenerate() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Regenerate")
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .controlSize(.small)
                    .help("Dismiss")
                }
            }
        }
    }

    private func failedRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            Button("Retry") { regenerate() }
                .controlSize(.small)
            Button { dismiss() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func regenerate() {
        guard let cid = connectionID, let buf = buffer else { return }
        model.assistant.requestSuggestion(
            connectionID: cid, bufferID: buf.id,
            historyProvider: { [weak conn = model.activeConnection] in
                conn?.buffers.first(where: { $0.id == buf.id })?.lines ?? []
            })
    }

    private func dismiss() {
        guard let buf = buffer else { return }
        model.assistant.dismissSuggestion(bufferID: buf.id)
    }

    private func disengage() {
        // Routes through the same toggle the /assist command uses so
        // the buffer gets an info line for the user's history.
        model.toggleAssistantOnSelected()
    }
}
