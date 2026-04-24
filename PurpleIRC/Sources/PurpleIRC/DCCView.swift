import SwiftUI
import AppKit

struct DCCView: View {
    @EnvironmentObject var model: ChatModel
    @ObservedObject var service: DCCService
    @State private var tab: Tab = .transfers

    enum Tab: String, CaseIterable, Identifiable {
        case transfers = "Transfers"
        case chats = "Chats"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DCC")
                    .font(.title2.bold())
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button("Clear finished") { service.clearInactive() }
                Button("Close") { model.showDCC = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Group {
                switch tab {
                case .transfers: transfersPane
                case .chats: chatsPane
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: - Transfers

    private var transfersPane: some View {
        Group {
            if service.transfers.isEmpty {
                ContentUnavailableView(
                    "No DCC transfers",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Use /dcc send <nick> to offer a file. Incoming offers from others will also show up here.")
                )
                .padding(40)
            } else {
                List {
                    ForEach(service.transfers) { t in
                        TransferRow(transfer: t, service: service)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var chatsPane: some View {
        Group {
            if service.chats.isEmpty {
                ContentUnavailableView(
                    "No DCC chats",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Use /dcc chat <nick> to start one. Incoming invites show up here.")
                )
                .padding(40)
            } else {
                List {
                    ForEach(service.chats) { c in
                        ChatRow(chat: c, service: service)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct TransferRow: View {
    @ObservedObject var transfer: DCCTransfer
    @ObservedObject var service: DCCService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: transfer.direction == .sending
                      ? "arrow.up.circle" : "arrow.down.circle")
                VStack(alignment: .leading) {
                    Text(transfer.filename).font(.body)
                    Text("\(transfer.direction == .sending ? "→" : "←") \(transfer.peerNick) • \(formatBytes(transfer.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                actionButtons
            }
            if showProgress {
                ProgressView(value: transfer.progress)
                HStack {
                    Text("\(formatBytes(transfer.bytesTransferred)) / \(formatBytes(transfer.totalBytes))")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var stateText: String {
        switch transfer.state {
        case .offered: return "offered"
        case .listening: return "waiting for peer"
        case .connecting: return "connecting"
        case .transferring: return "in progress"
        case .completed: return "done"
        case .failed(let msg): return "failed: \(msg)"
        case .cancelled: return "cancelled"
        }
    }
    private var stateColor: Color {
        switch transfer.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        default: return .blue
        }
    }
    private var showProgress: Bool {
        switch transfer.state {
        case .transferring, .completed: return true
        default: return false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch transfer.state {
        case .offered where transfer.direction == .receiving:
            Button("Accept") { accept() }.buttonStyle(.borderedProminent)
            Button("Reject") { service.cancelTransfer(transfer) }
        case .transferring, .listening, .connecting:
            Button("Cancel") { service.cancelTransfer(transfer) }
        case .completed:
            if let dst = transfer.destinationURL {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([dst])
                }
            }
        case .failed, .cancelled:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func accept() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = transfer.filename
        panel.directoryURL = service.downloadsDir
        panel.canCreateDirectories = true
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else {
                service.cancelTransfer(transfer)
                return
            }
            Task { @MainActor in
                service.acceptTransfer(transfer, savingTo: url)
            }
        }
    }

    private func formatBytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

private struct ChatRow: View {
    @ObservedObject var chat: DCCChatSession
    @ObservedObject var service: DCCService
    @State private var draft: String = ""
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: chat.direction == .sending
                      ? "bubble.right" : "bubble.left")
                Text(chat.peerNick).font(.body.bold())
                Text(stateText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                actionButtons
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
            }
            if expanded {
                chatLog
                if case .transferring = chat.state {
                    HStack {
                        TextField("Type a line and press Return", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submit() }
                        Button("Send") { submit() }
                            .disabled(draft.isEmpty)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var chatLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(chat.lines) { l in
                    HStack(alignment: .firstTextBaseline) {
                        Text(l.isSelf ? "me" : chat.peerNick)
                            .foregroundStyle(l.isSelf ? .blue : .purple)
                            .font(.caption.bold())
                            .frame(width: 60, alignment: .trailing)
                        Text(l.text)
                            .textSelection(.enabled)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        service.sendChat(chat, text: text)
        draft = ""
    }

    private var stateText: String {
        switch chat.state {
        case .offered: return "offered"
        case .listening: return "waiting"
        case .connecting: return "connecting"
        case .transferring: return "connected"
        case .completed: return "closed"
        case .failed(let msg): return "failed: \(msg)"
        case .cancelled: return "cancelled"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch chat.state {
        case .offered where chat.direction == .receiving:
            Button("Accept") { service.acceptChat(chat); expanded = true }
                .buttonStyle(.borderedProminent)
            Button("Reject") { service.cancelChat(chat) }
        case .transferring, .listening, .connecting:
            Button("End") { service.cancelChat(chat) }
        default:
            EmptyView()
        }
    }
}
