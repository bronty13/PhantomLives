import Foundation
import JavaScriptCore
import Combine

/// PurpleBot — the in-app scripting host. Wraps a single `JSContext`, exposes
/// an `irc` / `console` surface to JS, and fans out every `IRCConnectionEvent`
/// from `ChatModel.events` to whatever JS handlers have registered.
///
/// Scripts live on disk as `<supportDir>/scripts/<slug>-<rand>.js`, indexed by
/// `scripts/index.json` which tracks display name + enabled flag. Reload
/// rebuilds the JSContext from scratch — there is no hot-edit; toggling
/// `enabled` or saving a script re-executes everything.
///
/// Bot event model (stringly-typed, JS-friendly):
///   - `privmsg`  { networkId, networkName, from, target, text, isAction, isMention }
///   - `notice`   { networkId, networkName, from, target, text }
///   - `join`     { networkId, networkName, nick, channel, isSelf }
///   - `part`     { networkId, networkName, nick, channel, reason, isSelf }
///   - `quit`     { networkId, networkName, nick, reason }
///   - `topic`    { networkId, networkName, channel, topic, setter }
///   - `ctcp`     { networkId, networkName, from, target, command, args }
///   - `away`     { networkId, networkName, isAway, reason }
///   - `ignored`  { networkId, networkName, from, target }
///   - `state`    { networkId, networkName, state }
///   - `inbound`  { networkId, networkName, command, params, prefix }
///   - `outbound` { networkId, networkName, line }
///   - `nick`     { networkId, networkName, nick }
@MainActor
final class BotHost: ObservableObject {
    @Published var scripts: [BotScript] = []
    @Published private(set) var logLines: [BotLogLine] = []

    private let scriptsDir: URL
    private let indexURL: URL

    private var context: JSContext?
    private var eventHandlers: [String: [JSValue]] = [:]
    private var commandHandlers: [String: JSValue] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var nextTimerID = 1

    private weak var chatModel: ChatModel?
    private var cancellable: AnyCancellable?

    struct BotScript: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var name: String
        var enabled: Bool = true
        /// Relative filename under scriptsDir.
        var filename: String
    }

    struct BotLogLine: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let level: Level
        let text: String
        enum Level { case info, error, script }
    }

    init(supportDir: URL) {
        let dir = supportDir.appendingPathComponent("scripts", isDirectory: true)
        self.scriptsDir = dir
        self.indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadIndex()
    }

    /// Wire the shared event stream. Called once from ChatModel after init.
    func attach(_ model: ChatModel) {
        self.chatModel = model
        cancellable = model.events.sink { [weak self] tuple in
            guard let self else { return }
            self.handleEvent(networkID: tuple.0, event: tuple.1)
        }
        rebuildContext()
    }

    var scriptsDirectoryURL: URL { scriptsDir }

    // MARK: - Script storage

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([BotScript].self, from: data) else {
            scripts = []
            return
        }
        scripts = decoded
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(scripts) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func scriptSource(_ script: BotScript) -> String {
        let url = scriptsDir.appendingPathComponent(script.filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func writeScript(_ script: BotScript, source: String) {
        let url = scriptsDir.appendingPathComponent(script.filename)
        try? source.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func addScript(name: String, source: String) -> BotScript {
        let slug = fileSafe(name.isEmpty ? "script" : name)
        let rand = UUID().uuidString.prefix(6).lowercased()
        let s = BotScript(name: name.isEmpty ? "untitled" : name,
                          filename: "\(slug)-\(rand).js")
        writeScript(s, source: source)
        scripts.append(s)
        saveIndex()
        rebuildContext()
        return s
    }

    func update(_ script: BotScript, name: String, source: String, enabled: Bool) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[i].name = name
        scripts[i].enabled = enabled
        writeScript(scripts[i], source: source)
        saveIndex()
        rebuildContext()
    }

    func remove(_ script: BotScript) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        let url = scriptsDir.appendingPathComponent(scripts[i].filename)
        try? FileManager.default.removeItem(at: url)
        scripts.remove(at: i)
        saveIndex()
        rebuildContext()
    }

    func setEnabled(_ script: BotScript, _ enabled: Bool) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[i].enabled = enabled
        saveIndex()
        rebuildContext()
    }

    func reloadAll() {
        rebuildContext()
    }

    // MARK: - JSContext

    private func rebuildContext() {
        for (_, t) in timers { t.cancel() }
        timers.removeAll()
        eventHandlers.removeAll()
        commandHandlers.removeAll()

        guard let ctx = JSContext() else {
            appendLog(.error, "Failed to create JSContext")
            return
        }
        ctx.exceptionHandler = { [weak self] _, exception in
            guard let self else { return }
            let msg = exception?.toString() ?? "?"
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
            self.appendLog(.error, "Uncaught (line \(line)): \(msg)")
        }

        installGlobals(on: ctx)

        for s in scripts where s.enabled {
            let src = scriptSource(s)
            ctx.evaluateScript(src, withSourceURL: URL(string: "purple-bot:///\(s.filename)"))
            appendLog(.info, "Loaded \(s.name)")
        }
        context = ctx
    }

    private func installGlobals(on ctx: JSContext) {
        // console.log
        let consoleLog: @convention(block) (String) -> Void = { [weak self] text in
            DispatchQueue.main.async { self?.appendLog(.script, text) }
        }
        let console = JSValue(newObjectIn: ctx)!
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)

        let irc = JSValue(newObjectIn: ctx)!

        // irc.send(networkNameOrId, rawLine)
        let sendBlock: @convention(block) (String, String) -> Void = { [weak self] net, line in
            Task { @MainActor in self?.sendOnNetwork(name: net, line: line) }
        }
        irc.setObject(sendBlock, forKeyedSubscript: "send" as NSString)

        // irc.sendActive(rawLine)
        let sendActiveBlock: @convention(block) (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.sendOnActive(line) }
        }
        irc.setObject(sendActiveBlock, forKeyedSubscript: "sendActive" as NSString)

        // irc.msg(target, text) — PRIVMSG on the active connection.
        let msgBlock: @convention(block) (String, String) -> Void = { [weak self] target, text in
            Task { @MainActor in
                self?.sendOnActive("PRIVMSG \(target) :\(text)")
            }
        }
        irc.setObject(msgBlock, forKeyedSubscript: "msg" as NSString)

        // irc.notice(target, text) — NOTICE on the active connection.
        let noticeBlock: @convention(block) (String, String) -> Void = { [weak self] target, text in
            Task { @MainActor in
                self?.sendOnActive("NOTICE \(target) :\(text)")
            }
        }
        irc.setObject(noticeBlock, forKeyedSubscript: "notice" as NSString)

        // irc.on(eventName, callback)
        let onBlock: @convention(block) (String, JSValue) -> Void = { [weak self] name, cb in
            self?.eventHandlers[name.lowercased(), default: []].append(cb)
        }
        irc.setObject(onBlock, forKeyedSubscript: "on" as NSString)

        // irc.onCommand("foo", cb(args)) — registers /foo
        let onCmdBlock: @convention(block) (String, JSValue) -> Void = { [weak self] cmd, cb in
            self?.commandHandlers[cmd.lowercased()] = cb
        }
        irc.setObject(onCmdBlock, forKeyedSubscript: "onCommand" as NSString)

        // irc.setTimer(ms, cb) → id ; repeats forever until cleared.
        let setTimerBlock: @convention(block) (Int, JSValue) -> Int = { [weak self] ms, cb in
            guard let self else { return 0 }
            let id = self.nextTimerID; self.nextTimerID += 1
            self.timers[id] = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(max(10, ms)) * 1_000_000)
                    if Task.isCancelled { return }
                    cb.call(withArguments: [])
                }
            }
            return id
        }
        irc.setObject(setTimerBlock, forKeyedSubscript: "setTimer" as NSString)

        // irc.setTimeout(ms, cb) → id ; fires once.
        let setTimeoutBlock: @convention(block) (Int, JSValue) -> Int = { [weak self] ms, cb in
            guard let self else { return 0 }
            let id = self.nextTimerID; self.nextTimerID += 1
            self.timers[id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(10, ms)) * 1_000_000)
                if Task.isCancelled { return }
                cb.call(withArguments: [])
                self.timers.removeValue(forKey: id)
            }
            return id
        }
        irc.setObject(setTimeoutBlock, forKeyedSubscript: "setTimeout" as NSString)

        // irc.clearTimer(id)
        let clearTimerBlock: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers[id]?.cancel()
            self?.timers.removeValue(forKey: id)
        }
        irc.setObject(clearTimerBlock, forKeyedSubscript: "clearTimer" as NSString)

        // irc.networks() — snapshot of all connections for introspection.
        let networksBlock: @convention(block) () -> [[String: Any]] = { [weak self] in
            guard let model = self?.chatModel else { return [] }
            return model.connections.map { c in
                [
                    "id": c.id.uuidString,
                    "name": c.displayName,
                    "state": Self.stateString(c.state),
                    "nick": c.nick,
                    "channels": c.buffers.filter { $0.isChannel }.map { $0.name }
                ]
            }
        }
        irc.setObject(networksBlock, forKeyedSubscript: "networks" as NSString)

        // irc.activeNetwork() — or an empty object when there is none.
        let activeBlock: @convention(block) () -> [String: Any] = { [weak self] in
            guard let c = self?.chatModel?.activeConnection else { return [:] }
            return ["id": c.id.uuidString, "name": c.displayName, "nick": c.nick]
        }
        irc.setObject(activeBlock, forKeyedSubscript: "activeNetwork" as NSString)

        // irc.notify(text) — post an info line to the user's selected buffer.
        let notifyBlock: @convention(block) (String) -> Void = { [weak self] text in
            Task { @MainActor in self?.chatModel?.activeConnection?.appendInfoOnSelected(text) }
        }
        irc.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)

        ctx.setObject(irc, forKeyedSubscript: "irc" as NSString)
    }

    private static func stateString(_ s: IRCConnectionState) -> String {
        switch s {
        case .disconnected: return "disconnected"
        case .connecting:   return "connecting"
        case .connected:    return "connected"
        case .failed:       return "failed"
        }
    }

    // MARK: - Event dispatch

    private func handleEvent(networkID: UUID, event: IRCConnectionEvent) {
        guard let ctx = context else { return }
        let networkName = chatModel?.connections.first(where: { $0.id == networkID })?.displayName ?? ""
        let (kind, payload) = toJSObject(networkID: networkID, networkName: networkName, event: event)
        // Also fire generic "event" so scripts can log/observe everything.
        fire(ctx: ctx, kind: "event", payload: payload.merging(["kind": kind]) { a, _ in a })
        fire(ctx: ctx, kind: kind, payload: payload)
    }

    private func fire(ctx: JSContext, kind: String, payload: [String: Any]) {
        guard let handlers = eventHandlers[kind], !handlers.isEmpty else { return }
        let value = JSValue(object: payload, in: ctx) ?? JSValue(nullIn: ctx)!
        for h in handlers {
            h.call(withArguments: [value])
        }
    }

    private func toJSObject(networkID: UUID,
                            networkName: String,
                            event: IRCConnectionEvent) -> (String, [String: Any]) {
        let base: [String: Any] = [
            "networkId": networkID.uuidString,
            "networkName": networkName
        ]
        func merge(_ extra: [String: Any]) -> [String: Any] {
            base.merging(extra) { _, new in new }
        }
        switch event {
        case .privmsg(let from, let target, let text, let isAction, let isMention):
            return ("privmsg", merge([
                "from": from, "target": target, "text": text,
                "isAction": isAction, "isMention": isMention
            ]))
        case .notice(let from, let target, let text):
            return ("notice", merge(["from": from, "target": target, "text": text]))
        case .join(let nick, let channel, let isSelf):
            return ("join", merge(["nick": nick, "channel": channel, "isSelf": isSelf]))
        case .part(let nick, let channel, let reason, let isSelf):
            return ("part", merge([
                "nick": nick, "channel": channel,
                "reason": reason ?? NSNull(), "isSelf": isSelf
            ]))
        case .quit(let nick, let reason):
            return ("quit", merge(["nick": nick, "reason": reason ?? NSNull()]))
        case .topic(let channel, let topic, let setter):
            return ("topic", merge(["channel": channel, "topic": topic, "setter": setter ?? NSNull()]))
        case .ctcpRequest(let from, let target, let command, let args):
            return ("ctcp", merge(["from": from, "target": target, "command": command, "args": args]))
        case .awayChanged(let isAway, let reason):
            return ("away", merge(["isAway": isAway, "reason": reason ?? NSNull()]))
        case .ignoredMessage(let from, let target):
            return ("ignored", merge(["from": from, "target": target]))
        case .state(let state):
            return ("state", merge(["state": Self.stateString(state)]))
        case .inbound(let msg):
            return ("inbound", merge([
                "command": msg.command,
                "params": msg.params,
                "prefix": msg.prefix ?? NSNull()
            ]))
        case .outbound(let line):
            return ("outbound", merge(["line": line]))
        case .ownNickChanged(let nick):
            return ("nick", merge(["nick": nick]))
        case .nickChanged(let old, let new, let isSelf):
            return ("nickchange", merge(["old": old, "new": new, "isSelf": isSelf]))
        }
    }

    // MARK: - Command alias dispatch

    /// Return true if a JS-registered /alias claimed the command.
    func handleCommandAlias(_ cmd: String, args: String) -> Bool {
        guard let handler = commandHandlers[cmd.lowercased()] else { return false }
        handler.call(withArguments: [args])
        return true
    }

    // MARK: - Outbound helpers

    private func sendOnActive(_ line: String) {
        chatModel?.activeConnection?.sendRaw(line)
    }

    private func sendOnNetwork(name: String, line: String) {
        guard let model = chatModel else { return }
        if let conn = model.connections.first(where: {
            $0.displayName == name || $0.id.uuidString == name
        }) {
            conn.sendRaw(line)
        }
    }

    // MARK: - Logging

    private func appendLog(_ level: BotLogLine.Level, _ text: String) {
        logLines.append(BotLogLine(level: level, text: text))
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    // MARK: - Helpers

    private func fileSafe(_ name: String) -> String {
        let bad: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\0", " "]
        return String(name.lowercased().map { bad.contains($0) ? "_" : $0 })
    }
}
