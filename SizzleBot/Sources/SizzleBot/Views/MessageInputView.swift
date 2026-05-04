import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachments: [Attachment]
    let isGenerating: Bool
    let accentColor: Color
    let acceptsImages: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool
    @State private var isDropTargeted = false

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return (hasText || hasAttachments) && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty {
                AttachmentTray(attachments: $attachments)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if acceptsImages {
                    Button {
                        pickImage()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.borderless)
                    .help("Attach an image")
                }

                TextField(textFieldPrompt, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.quaternarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isDropTargeted ? accentColor : .clear, lineWidth: 2)
                    )
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { focused = true }
        .onDrop(of: [.image, .fileURL], isTargeted: acceptsImages ? $isDropTargeted : .constant(false)) { providers in
            guard acceptsImages else { return false }
            handleDrop(providers: providers)
            return true
        }
    }

    private var textFieldPrompt: String {
        if acceptsImages {
            return attachments.isEmpty ? "Message or drop an image…" : "Add a note (optional)…"
        }
        return "Message…"
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose a photo"
        if panel.runModal() == .OK, let url = panel.url {
            addAttachment(from: url)
        }
    }

    private func addAttachment(from url: URL) {
        do {
            let base64 = try ImageAttachment.encode(fileURL: url)
            attachments.append(Attachment(base64: base64, sourceName: url.lastPathComponent))
        } catch {
            // Silent — the chat surface already shows generation errors;
            // a load failure here is rare enough we just no-op.
        }
    }

    private func addAttachment(from data: Data, name: String) {
        do {
            let base64 = try ImageAttachment.encode(data: data)
            attachments.append(Attachment(base64: base64, sourceName: name))
        } catch {}
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage,
                          let tiff = image.tiffRepresentation else { return }
                    DispatchQueue.main.async {
                        addAttachment(from: tiff, name: "Dropped image")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async { addAttachment(from: url) }
                    } else if let url = item as? URL {
                        DispatchQueue.main.async { addAttachment(from: url) }
                    }
                }
            }
        }
    }
}

struct Attachment: Identifiable, Hashable {
    let id = UUID()
    let base64: String
    let sourceName: String
}

private struct AttachmentTray: View {
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    AttachmentChip(attachment: att) {
                        attachments.removeAll { $0.id == att.id }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 72)
    }
}

private struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = ImageAttachment.decode(base64: attachment.base64) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .offset(x: 6, y: -6)
            .help("Remove attachment")
        }
        .help(attachment.sourceName)
    }
}
