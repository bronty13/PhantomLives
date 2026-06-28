import SwiftUI

/// Settings ▸ Hosts: manage the machines PurpleMirror monitors. The local Mac is always present;
/// add the dedicated runner (or any Mac) by its SSH details so its jobs appear alongside local
/// ones. Monitoring + Run Now work for remote jobs now; schedule editing is a later phase.
struct HostsSettingsView: View {
    @ObservedObject var model: JobsModel
    @Environment(\.openURL) private var openURL

    @State private var newName = ""
    @State private var newUser = ""
    @State private var newHost = ""
    @State private var newPort = "22"
    @State private var newKey = ""
    @State private var testResult: [String: String] = [:]   // host.id → message
    @State private var testing: Set<String> = []
    @State private var addError: String?

    var body: some View {
        Form {
            Section("Monitored hosts") {
                ForEach(model.monitoredHosts) { host in
                    HStack(spacing: 10) {
                        Image(systemName: host.isLocal ? "desktopcomputer" : "network")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(host.displayName).fontWeight(.medium)
                                if host.fromFleet {
                                    Text("FLEET").font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(.tint.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(host.isLocal ? "this machine" : host.sshTarget)
                                .font(.caption).foregroundStyle(.secondary)
                            if let msg = testResult[host.id] {
                                Text(msg).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if !host.isLocal {
                            // Quick-connect: SSH (Terminal), SMB (Finder), Screen Sharing (VNC)
                            HStack(spacing: 1) {
                                connectButton("terminal", host.sshURLString, "SSH to \(host.displayName) (Terminal)")
                                connectButton("folder", host.smbURLString, "Open file sharing (SMB) on \(host.displayName)")
                                connectButton("display", host.vncURLString, "Screen Sharing (VNC) to \(host.displayName)")
                            }
                            .foregroundStyle(.secondary)
                            if testing.contains(host.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Test") { test(host) }.buttonStyle(.bordered)
                            }
                            // Fleet hosts are managed in fleet.json, not removable here.
                            if !host.fromFleet {
                                Button(role: .destructive) { remove(host) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Stop monitoring \(host.displayName)")
                            }
                        }
                    }
                }
            }

            Section("Add a remote host (SSH)") {
                TextField("Display name", text: $newName, prompt: Text("e.g. Runner"))
                TextField("SSH user", text: $newUser, prompt: Text("e.g. bronty"))
                TextField("Host or IP", text: $newHost, prompt: Text("e.g. 10.0.0.50"))
                TextField("Port", text: $newPort)   // 22 is a real default, not a placeholder
                TextField("Identity file (optional)", text: $newKey,
                          prompt: Text("e.g. ~/.ssh/id_ed25519"))
                Button("Add Host") { add() }
                    .disabled(!canAdd)
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !canAdd {
                    Text("Enter a display name, SSH user, and host to add.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("The remote Mac must have **Remote Login** enabled (System Settings ▸ General ▸ Sharing) and this Mac's SSH public key in its `~/.ssh/authorized_keys`. Connections are key-only — a missing key fails fast rather than prompting. Monitoring and **Run Now** work for remote jobs; schedule editing is local-only for now.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Per-host shortcuts: \(Image(systemName: "terminal")) SSH (Terminal) · \(Image(systemName: "folder")) file sharing (SMB, needs **File Sharing** on the remote) · \(Image(systemName: "display")) Screen Sharing (VNC, needs **Screen Sharing** / Remote Management on the remote).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var canAdd: Bool {
        !newName.trimmed.isEmpty && !newUser.trimmed.isEmpty && !newHost.trimmed.isEmpty
    }

    // MARK: Connect shortcuts

    @ViewBuilder
    private func connectButton(_ symbol: String, _ urlString: String?, _ help: String) -> some View {
        Button {
            if let s = urlString, let url = URL(string: s) { openURL(url) }
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(urlString == nil)
    }

    // MARK: Actions

    private func add() {
        addError = nil
        let id = slug(newName)
        if HostStore.load().contains(where: { $0.id == id }) {
            addError = "A host named “\(newName.trimmed)” already exists."; return
        }
        // Validate the identity file up front — a mistyped key path is the easiest way to add a
        // host that silently never connects (it just shows no jobs).
        var key: String? = newKey.trimmed
        if let k = key, !k.isEmpty {
            if !FileManager.default.fileExists(atPath: (k as NSString).expandingTildeInPath) {
                addError = "Identity file not found:\n\(k)"; return
            }
        } else {
            key = nil
        }
        let port = Int(newPort.trimmed) ?? 22
        var hosts = HostStore.load()
        hosts.append(.remote(id: id, displayName: newName.trimmed, user: newUser.trimmed,
                             host: newHost.trimmed, port: port, identityFile: key))
        HostStore.save(hosts)
        model.reloadHosts()
        newName = ""; newUser = ""; newHost = ""; newPort = "22"; newKey = ""
    }

    private func remove(_ host: MonitoredHost) {
        HostStore.save(HostStore.load().filter { $0.id != host.id })
        testResult[host.id] = nil
        model.reloadHosts()
    }

    private func test(_ host: MonitoredHost) {
        testing.insert(host.id)
        testResult[host.id] = nil
        Task {
            let ctx = HostContext(host: host)
            await ctx.ensureResolved()
            let (st, out) = await ctx.shell("echo purplemirror-ok")
            testing.remove(host.id)
            if st == 0, out.contains("purplemirror-ok") {
                testResult[host.id] = "✓ Connected (uid \(ctx.uid), home \(ctx.home))"
            } else {
                let m = out.trimmingCharacters(in: .whitespacesAndNewlines)
                testResult[host.id] = "✗ " + (m.isEmpty ? "Could not connect — check the key and Remote Login" : m)
            }
        }
    }

    /// Stable id slug from the display name (letters/digits/hyphens).
    private func slug(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: " ", with: "-")
        let allowed = String(lowered.filter { $0.isLetter || $0.isNumber || $0 == "-" })
        return allowed.isEmpty ? "host-\(UInt(bitPattern: s.hashValue))" : allowed
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
