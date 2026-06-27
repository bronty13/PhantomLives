import SwiftUI

/// Settings ▸ Hosts: manage the machines PurpleMirror monitors. The local Mac is always present;
/// add the dedicated runner (or any Mac) by its SSH details so its jobs appear alongside local
/// ones. Monitoring + Run Now work for remote jobs now; schedule editing is a later phase.
struct HostsSettingsView: View {
    @ObservedObject var model: JobsModel

    @State private var newName = ""
    @State private var newUser = ""
    @State private var newHost = ""
    @State private var newPort = "22"
    @State private var newKey = ""
    @State private var testResult: [String: String] = [:]   // host.id → message
    @State private var testing: Set<String> = []

    var body: some View {
        Form {
            Section("Monitored hosts") {
                ForEach(model.monitoredHosts) { host in
                    HStack(spacing: 10) {
                        Image(systemName: host.isLocal ? "desktopcomputer" : "network")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.displayName).fontWeight(.medium)
                            Text(host.isLocal ? "this machine" : host.sshTarget)
                                .font(.caption).foregroundStyle(.secondary)
                            if let msg = testResult[host.id] {
                                Text(msg).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if !host.isLocal {
                            if testing.contains(host.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Test") { test(host) }.buttonStyle(.bordered)
                            }
                            Button(role: .destructive) { remove(host) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop monitoring \(host.displayName)")
                        }
                    }
                }
            }

            Section("Add a remote host (SSH)") {
                TextField("Display name", text: $newName, prompt: Text("Runner"))
                TextField("SSH user", text: $newUser, prompt: Text("bronty"))
                TextField("Host or IP", text: $newHost, prompt: Text("10.0.0.50"))
                TextField("Port", text: $newPort)
                TextField("Identity file (optional)", text: $newKey,
                          prompt: Text("~/.ssh/purplemirror_runner"))
                Button("Add Host") { add() }
                    .disabled(newName.trimmed.isEmpty || newUser.trimmed.isEmpty || newHost.trimmed.isEmpty)
            }

            Section {
                Text("The remote Mac must have **Remote Login** enabled (System Settings ▸ General ▸ Sharing) and this Mac's SSH public key in its `~/.ssh/authorized_keys`. Connections are key-only — a missing key fails fast rather than prompting. Monitoring and **Run Now** work for remote jobs; schedule editing is local-only for now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func add() {
        let id = slug(newName)
        var hosts = HostStore.load()
        guard !hosts.contains(where: { $0.id == id }) else {
            testResult[id] = "A host named “\(newName.trimmed)” already exists"; return
        }
        let port = Int(newPort.trimmed) ?? 22
        let key = newKey.trimmed
        hosts.append(.remote(id: id, displayName: newName.trimmed, user: newUser.trimmed,
                             host: newHost.trimmed, port: port,
                             identityFile: key.isEmpty ? nil : key))
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
