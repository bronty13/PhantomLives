import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - PurpleBot scripts

struct ScriptsSetup: View {
    @ObservedObject var bot: BotHost
    @State private var selection: UUID?
    @State private var draftSource: String = ""
    @State private var draftName: String = ""
    @State private var draftEnabled: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(bot.scripts) { s in
                        HStack {
                            Image(systemName: s.enabled ? "bolt.fill" : "bolt.slash")
                                .foregroundStyle(s.enabled ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(s.name).font(.body)
                                Text(s.filename).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(s.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let s = bot.addScript(name: "new script", source: sampleScript)
                        selection = s.id
                        loadSelection()
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection,
                           let s = bot.scripts.first(where: { $0.id == id }) {
                            bot.remove(s)
                            selection = bot.scripts.first?.id
                            loadSelection()
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Reload all") { bot.reloadAll() }
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let script = bot.scripts.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Enabled", isOn: $draftEnabled)
                        Button("Save") {
                            bot.update(script, name: draftName,
                                       source: draftSource, enabled: draftEnabled)
                        }
                        .keyboardShortcut("s", modifiers: [.command])
                    }
                    TextEditor(text: $draftSource)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                    botLogView
                }
                .padding()
                .onAppear { loadSelection() }
                .onChange(of: selection) { _, _ in loadSelection() }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "curlybraces.square")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("PurpleBot — JavaScript scripting")
                        .font(.headline)
                    Text(helpText)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.horizontal)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = bot.scripts.first?.id }
            loadSelection()
        }
    }

    private func loadSelection() {
        guard let id = selection,
              let s = bot.scripts.first(where: { $0.id == id }) else {
            draftName = ""; draftSource = ""; draftEnabled = true
            return
        }
        draftName = s.name
        draftEnabled = s.enabled
        draftSource = bot.scriptSource(s)
    }

    private var botLogView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bot log").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(bot.logLines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line.level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 100, maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func color(for level: BotHost.BotLogLine.Level) -> Color {
        switch level {
        case .info:   return .secondary
        case .error:  return .red
        case .script: return .primary
        }
    }

    private let sampleScript = """
    // PurpleBot script — runs inside the app.
    // Docs (in-flight): irc.on(event, cb), irc.onCommand('name', cb),
    // irc.msg(target, text), irc.sendActive(raw), irc.setTimer(ms, cb).

    irc.on('privmsg', (e) => {
      if (e.isMention) {
        console.log('mentioned by ' + e.from + ' in ' + e.target + ': ' + e.text);
      }
    });

    irc.onCommand('hello', (args) => {
      irc.notify('Hello from PurpleBot! args: ' + args);
    });
    """

    private let helpText = """
    Write small scripts that react to IRC events or register /aliases.

    Select a script on the left — or hit + for a new one — to edit it. Press \
    Save (⌘S) to reload all scripts. Logs from console.log appear below the \
    editor.
    """
}

