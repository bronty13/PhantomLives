import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isGenerating: Bool
    let accentColor: Color
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.quaternarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit { if canSend { onSend() } }

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            } else {
                Button(action: onSend) {
                    Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? AnyShapeStyle(accentColor) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }
}
