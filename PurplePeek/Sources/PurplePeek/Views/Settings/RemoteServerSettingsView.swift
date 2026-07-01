import SwiftUI

/// Connect PurplePeek to a PeekServer on the LAN (remote mode). When enabled + applied, all roots,
/// items, and decisions come from the server instead of local folders. The password is stored in
/// the Keychain (never in settings JSON). "Test Connection" hits `/api/roots` with the entered
/// credentials; "Apply" persists + switches mode + refetches.
struct RemoteServerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: SettingsStore

    @State private var enabled = false
    @State private var host = ""
    @State private var portText = "8788"
    @State private var user = ""
    @State private var password = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    private var port: Int { Int(portText.trimmingCharacters(in: .whitespaces)) ?? 8788 }

    var body: some View {
        Form {
            Toggle("Use a PeekServer (remote mode)", isOn: $enabled)
            Text("Review media served by a PeekServer over the local network — thumbnails and decisions come from the server, so any Mac can review the same library. Turn off to use local folders on this Mac.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            LabeledContent("Host") {
                TextField("10.0.0.59", text: $host).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            LabeledContent("Port") {
                TextField("8788", text: $portText).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            LabeledContent("Username") {
                TextField("peek", text: $user).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            LabeledContent("Password") {
                SecureField("", text: $password).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .disabled(!enabled)

            HStack {
                Button("Test Connection") { test() }
                    .disabled(!enabled || host.isEmpty || testing)
                if testing { ProgressView().controlSize(.small) }
                if let testResult {
                    Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testOK ? .green : .red)
                        .font(.caption)
                }
            }

            Divider()

            HStack {
                if appState.isRemote {
                    Label("Connected — reviewing \(store.settings.peekServerHost)", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply") {
                    appState.applyPeekServerConnection(enabled: enabled, host: host.trimmingCharacters(in: .whitespaces),
                                                       port: port, user: user.trimmingCharacters(in: .whitespaces),
                                                       password: password)
                    testResult = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear(perform: loadCurrent)
    }

    private func loadCurrent() {
        let s = store.settings
        enabled = s.peekServerEnabled
        host = s.peekServerHost
        portText = String(s.peekServerPort)
        user = s.peekServerUser
        let conn = PeekServerConnection(host: s.peekServerHost, port: s.peekServerPort, user: s.peekServerUser)
        password = KeychainStore.password(account: conn.account) ?? ""
    }

    private func test() {
        testing = true
        testResult = nil
        let conn = PeekServerConnection(host: host.trimmingCharacters(in: .whitespaces), port: port,
                                        user: user.trimmingCharacters(in: .whitespaces))
        let client = PeekServerClient(connection: conn, password: password)
        Task {
            do {
                let roots = try await client.roots()
                let files = roots.reduce(0) { $0 + $1.total }
                testResult = "OK — \(roots.count) root(s), \(files) file(s)"
                testOK = true
            } catch {
                testResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                testOK = false
            }
            testing = false
        }
    }
}
