import SwiftUI

/// Modal sheet listing slackdump workspaces with add / select / delete.
/// "Add" spawns `slackdump workspace new <name>`, which opens slackdump's
/// own EZ-Login browser flow. SlackSucker pipes the child's stdin/stdout
/// so prompts (e.g. "Overwrite? (y/N)" when a name collides) can be
/// answered via a confirm dialog instead of busy-looping forever.
struct WorkspaceSheet: View {
    @EnvironmentObject var workspaces: WorkspaceService
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete: String?
    @State private var newWorkspaceName: String = ""
    @State private var showAddForm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Slack workspaces")
                    .font(AppFont.display(16, weight: .semibold))
                Spacer()
                Button(action: { Task { await workspaces.refresh() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if workspaces.workspaces.isEmpty {
                Text("No workspaces yet. Click \u{201C}Add workspace\u{201D} to sign in.")
                    .font(AppFont.sans(13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(workspaces.workspaces) { ws in
                        HStack {
                            Text(ws.name)
                                .font(AppFont.sans(13, weight: ws.name == settings.selectedWorkspace ? .bold : .regular))
                            if ws.isCurrent {
                                Text("· current")
                                    .font(AppFont.sans(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if ws.name == settings.selectedWorkspace {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Select") {
                                    settings.selectedWorkspace = ws.name
                                    settings.save()
                                    Task { await workspaces.select(ws.name) }
                                }
                                .buttonStyle(.borderless)
                            }
                            Button {
                                confirmDelete = ws.name
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 120)
            }

            Divider()

            addSection

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .alert("Remove workspace?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let name = confirmDelete {
                    Task { await workspaces.delete(name) }
                    if settings.selectedWorkspace == name {
                        settings.selectedWorkspace = nil
                        settings.save()
                    }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This wipes slackdump's saved credentials for \(confirmDelete ?? ""). You'll need to re-authenticate to use it again.")
        }
        .alert("Workspace already exists",
               isPresented: Binding(
                get: { workspaces.pendingOverwritePrompt != nil },
                set: { if !$0 && workspaces.pendingOverwritePrompt != nil {
                    workspaces.answerOverwrite(yes: false)
                } })
        ) {
            Button("Overwrite", role: .destructive) {
                workspaces.answerOverwrite(yes: true)
            }
            Button("Cancel", role: .cancel) {
                workspaces.answerOverwrite(yes: false)
            }
        } message: {
            Text("A workspace named \u{201C}\(workspaces.pendingOverwritePrompt ?? "")\u{201D} already exists. Overwrite its saved credentials with a fresh login?")
        }
        .onAppear {
            Task { await workspaces.refresh() }
        }
        // After a successful `workspace new`, slackdump has already
        // marked the new workspace as current in its own cache — mirror
        // that into SettingsStore so SlackSucker uses it without the
        // user having to click "Select" themselves.
        .onChange(of: workspaces.lastAddedWorkspaceName) { _, newValue in
            guard let name = newValue else { return }
            settings.selectedWorkspace = name
            settings.save()
            Task {
                await workspaces.select(name)
                workspaces.acknowledgeLastAdded()
            }
        }
    }

    // MARK: - Add section

    @ViewBuilder
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !showAddForm && !workspaces.isBusy {
                HStack {
                    Button {
                        showAddForm = true
                    } label: {
                        Label("Add workspace…", systemImage: "person.crop.circle.badge.plus")
                    }
                    Spacer()
                }
            } else if showAddForm && !workspaces.isBusy {
                // Pre-flight form: ask for the workspace URL/name BEFORE
                // spawning slackdump. If the name collides with an
                // existing entry, slackdump's overwrite prompt is now
                // routed through a real alert instead of busy-looping.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workspace URL or name")
                        .font(AppFont.kicker())
                        .foregroundStyle(.secondary)
                    TextField("https://yourteam.slack.com or yourteam",
                              text: $newWorkspaceName)
                        .textFieldStyle(.roundedBorder)
                    Text("Slackdump opens its own browser-based login (EZ-Login 3000) when you continue. Leave blank to use the name \u{201C}default\u{201D}.")
                        .font(AppFont.sans(11))
                        .foregroundStyle(.tertiary)
                    Text("Tip: if Slack offers to open the desktop app, choose \u{201C}use Slack in your browser\u{201D} instead — the hijacker can only capture credentials from the web session.")
                        .font(AppFont.sans(11))
                        .foregroundStyle(.tertiary)
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            showAddForm = false
                            newWorkspaceName = ""
                        }
                        Button("Sign in") {
                            let nameToUse = newWorkspaceName
                            Task {
                                await workspaces.addNewWorkspace(name: nameToUse)
                                showAddForm = false
                                newWorkspaceName = ""
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else if workspaces.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Signing in… slackdump should open a browser window. Complete the Slack login there, then return here.")
                        .font(AppFont.sans(12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel auth") {
                        workspaces.cancelNewWorkspace()
                    }
                }
            }

            if !workspaces.newWorkspaceLog.isEmpty {
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(workspaces.newWorkspaceLog.indices, id: \.self) { i in
                                Text(workspaces.newWorkspaceLog[i])
                                    .font(AppFont.mono(11))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        let joined = workspaces.newWorkspaceLog.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(joined, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .padding(4)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy log to clipboard")
                    .padding(6)
                }
            }
            if let err = workspaces.lastError {
                Text(err)
                    .font(AppFont.sans(12))
                    .foregroundStyle(.red)
            }
        }
    }
}
