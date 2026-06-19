import SwiftUI
import UniformTypeIdentifiers

/// The Faces window — a grid of avatars for the users on the focused channel,
/// echoing classic Ircle's per-user picture window. Each face is an assigned
/// image or a generated monogram; per-face actions assign/remove the image or
/// start a query / whois.
struct FacesView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var faces: FacesStore

    private var palette: PlatinumPalette {
        .forAppearance(settingsStore.settings.appearance)
    }

    private var users: [IrcleUser] {
        guard let buffer = model.selectedBuffer else { return [] }
        switch buffer.kind {
        case .channel: return buffer.users
        case .query:   return [IrcleUser(nick: buffer.name, prefix: "")]
        case .server:  return []
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        let palette = palette
        VStack(spacing: 0) {
            header(palette)
            Divider().overlay(palette.hairline)
            if users.isEmpty {
                emptyState(palette)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(users) { user in
                            FaceCell(user: user, palette: palette)
                        }
                    }
                    .padding(14)
                }
                .background(palette.textBG)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .background(palette.windowBG)
    }

    private func header(_ palette: PlatinumPalette) -> some View {
        let title: String = {
            guard let b = model.selectedBuffer else { return "Faces" }
            switch b.kind {
            case .channel: return "\(b.name): \(b.users.count) face\(b.users.count == 1 ? "" : "s")"
            case .query:   return "\(b.name)"
            case .server:  return "Faces"
            }
        }()
        return HStack {
            Text(title).font(palette.chromeFontBold())
                .foregroundColor(palette.chromeText)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.paneBG)
    }

    private func emptyState(_ palette: PlatinumPalette) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No faces to show")
                .font(palette.chromeFontBold()).foregroundColor(palette.chromeText)
            Text("Select a channel to see the people in it.")
                .font(palette.chromeFont()).foregroundColor(palette.timestamp)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.textBG)
    }
}

private struct FaceCell: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var faces: FacesStore
    let user: IrcleUser
    let palette: PlatinumPalette

    var body: some View {
        VStack(spacing: 5) {
            AvatarView(nick: user.nick, size: 64)
            HStack(spacing: 2) {
                if !user.prefix.isEmpty {
                    Text(user.prefix).font(palette.chromeFontBold())
                        .foregroundColor(palette.errorText)
                }
                Text(user.nick)
                    .font(palette.chromeFont())
                    .foregroundColor(palette.chromeText)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 88)
        }
        .contextMenu {
            Button("Assign Image…") { assignImage() }
            if faces.hasImage(for: user.nick) {
                Button("Remove Image") { faces.clear(user.nick) }
            }
            Divider()
            Button("Query") { openQuery() }
            Button("Whois") { whois() }
        }
        .onTapGesture(count: 2) { openQuery() }
        .help(user.nick)
    }

    private func assignImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .image]
        panel.prompt = "Assign"
        if panel.runModal() == .OK, let url = panel.url {
            _ = try? faces.assign(imageAt: url, to: user.nick)
        }
    }

    private func openQuery() {
        guard let session = model.selectedSession else { return }
        model.select(session.ensureQuery(user.nick))
    }

    private func whois() {
        guard let buffer = model.selectedBuffer else { return }
        model.selectedSession?.runCommand("/whois \(user.nick)", in: buffer)
    }
}
