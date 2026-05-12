import SwiftUI
import AppKit
import MasterClipperCore

/// Three-step share-creation wizard:
///   1. Pick clips (filter by persona, search by title, multi-select).
///   2. Choose permission + expiry + optional label.
///   3. Confirm → ShareManager creates the share + shows the resulting URL,
///      which the user can copy or send via the macOS share menu.
struct CreateShareSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var manager = ShareManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .pickClips
    @State private var selectedClipIds: Set<String> = []
    @State private var permission: SharePermission = .readOnly
    @State private var expiryPreset: ExpiryPreset = .sevenDays
    @State private var customExpiry: Date = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var label: String = ""
    @State private var clipSearch: String = ""
    @State private var personaFilter: String? = nil

    @State private var inFlight: Bool = false
    @State private var resultURL: URL?
    @State private var errorText: String?

    enum Step { case pickClips, configure, result }

    enum ExpiryPreset: Hashable, CaseIterable {
        case oneDay, sevenDays, thirtyDays, custom

        var label: String {
            switch self {
            case .oneDay:     return "24 hours"
            case .sevenDays:  return "7 days"
            case .thirtyDays: return "30 days"
            case .custom:     return "Custom"
            }
        }

        func resolve(custom: Date) -> Date {
            switch self {
            case .oneDay:     return Date().addingTimeInterval(24 * 3600)
            case .sevenDays:  return Date().addingTimeInterval(7 * 24 * 3600)
            case .thirtyDays: return Date().addingTimeInterval(30 * 24 * 3600)
            case .custom:    return custom
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch step {
                case .pickClips:  clipPicker
                case .configure:  configurePage
                case .result:     resultPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 720, height: 560)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Create share").font(.title3.bold())
                Text(stepLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(selectedClipIds.count) selected").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private var stepLabel: String {
        switch step {
        case .pickClips: return "Step 1 of 3 — pick clips to share"
        case .configure: return "Step 2 of 3 — choose permission + expiry"
        case .result:    return "Step 3 of 3 — copy or send the link"
        }
    }

    // MARK: - Step 1: clip picker

    private var clipPicker: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search by title or ID", text: $clipSearch)
                    .textFieldStyle(.roundedBorder)
                Picker("Persona", selection: $personaFilter) {
                    Text("All personas").tag(String?.none)
                    ForEach(appState.personas) { p in
                        Text(p.code).tag(String?.some(p.code))
                    }
                }
                .frame(width: 180)
            }
            .padding(.horizontal)

            HStack {
                Button("Select all visible") {
                    selectedClipIds.formUnion(filteredClips.map(\.id))
                }
                Button("Clear selection") {
                    selectedClipIds.removeAll()
                }
                Spacer()
                Text("\(filteredClips.count) clips match")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .controlSize(.small)

            List(filteredClips, id: \.id) { clip in
                Toggle(isOn: Binding(
                    get: { selectedClipIds.contains(clip.id) },
                    set: { newVal in
                        if newVal { selectedClipIds.insert(clip.id) }
                        else { selectedClipIds.remove(clip.id) }
                    }
                )) {
                    HStack {
                        Text(clip.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(clip.title).lineLimit(1)
                        Spacer()
                        Text(clip.personaCode).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var filteredClips: [Clip] {
        appState.clips.filter { clip in
            if let p = personaFilter, clip.personaCode.caseInsensitiveCompare(p) != .orderedSame {
                return false
            }
            let q = clipSearch.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let needle = q.lowercased()
                if !clip.title.lowercased().contains(needle) && !clip.id.lowercased().contains(needle) {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Step 2: configure

    private var configurePage: some View {
        Form {
            Section("Recipient can") {
                Picker("Permission", selection: $permission) {
                    ForEach(SharePermission.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Text(permission == .readOnly
                     ? "Recipient can browse and search but cannot edit anything."
                     : "Recipient can mark posted, add notes, change status. Their edits sync back to your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Expires in") {
                Picker("Expiry", selection: $expiryPreset) {
                    ForEach(ExpiryPreset.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                if expiryPreset == .custom {
                    DatePicker("Expires at",
                               selection: $customExpiry,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                }
                Text("After this date the share is auto-revoked from your Mac and refuses to display on iOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Label (optional)") {
                TextField("e.g. \"Editor preview — May 2026\"", text: $label)
                Text("Helps you remember what this share was for. Visible to the recipient.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 3: result

    private var resultPage: some View {
        VStack(spacing: 16) {
            if let url = resultURL {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Share created").font(.title3.bold())
                Text("Send this link to the person you want to share with. Anyone with the link plus the **MasterClipper** iOS app and an Apple ID can accept it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                HStack {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button {
                        let picker = NSSharingServicePicker(items: [url])
                        if let window = NSApp.keyWindow,
                           let view = window.contentView {
                            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
                        }
                    } label: {
                        Label("Send…", systemImage: "square.and.arrow.up")
                    }
                }
                .padding(.horizontal, 40)

                Text("Expires \(formatExpiry(expiryPreset.resolve(custom: customExpiry)))")
                    .font(.caption).foregroundStyle(.secondary)

            } else if let err = errorText {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Couldn't create share").font(.title3.bold())
                Text(err).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .pickClips, step != .result {
                Button("Back") { step = previousStep() }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button(primaryButtonLabel) { Task { await primaryAction() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!primaryButtonEnabled || inFlight)
        }
        .padding()
        .overlay(alignment: .leading) {
            if inFlight { ProgressView().scaleEffect(0.7).padding(.leading) }
        }
    }

    private var primaryButtonLabel: String {
        switch step {
        case .pickClips: return "Next"
        case .configure: return "Create share"
        case .result:    return "Done"
        }
    }

    private var primaryButtonEnabled: Bool {
        switch step {
        case .pickClips: return !selectedClipIds.isEmpty
        case .configure: return true
        case .result:    return true
        }
    }

    private func previousStep() -> Step {
        switch step {
        case .pickClips: return .pickClips
        case .configure: return .pickClips
        case .result:    return .configure
        }
    }

    private func primaryAction() async {
        switch step {
        case .pickClips:
            step = .configure
        case .configure:
            inFlight = true
            do {
                let expiresAt = expiryPreset.resolve(custom: customExpiry)
                let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = try await ShareManager.shared.createShare(
                    clipIds: Array(selectedClipIds),
                    permission: permission,
                    expiresAt: expiresAt,
                    label: cleanLabel.isEmpty ? nil : cleanLabel
                )
                resultURL = url
                errorText = nil
            } catch {
                resultURL = nil
                errorText = error.localizedDescription
            }
            inFlight = false
            step = .result
        case .result:
            dismiss()
        }
    }

    private func formatExpiry(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
