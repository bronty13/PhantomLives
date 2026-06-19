import Foundation
import IRCKit
import JavaScriptCore
import Combine
import CryptoKit

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
///   - `nick`     { networkId, networkName, nick }            (own nick changed)
///   - `nickchange` { networkId, networkName, old, new, isSelf }
///   - `watchedQueryAutoOpened` { networkId, networkName, bufferID, from }
///
/// Every event also fans out under the generic `event` name with a `kind`
/// field added, so a handler can observe everything in one place.
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

    /// Ephemeral capability tokens minted fresh on every `rebuildContext`,
    /// mapping an opaque token → the script's persistent store id. Each
    /// script's wrapper closes over ONLY its own token (IIFE-local), and the
    /// store bridge resolves the token here. A script therefore can't reach
    /// another script's store by passing its UUID — the underscore bridge no
    /// longer trusts a JS-supplied id. Tokens are random per rebuild so they
    /// can't be guessed or carried across reloads.
    private var storeTokens: [String: UUID] = [:]

    /// Hard cap on concurrently-live JS timers across all scripts. Stops a
    /// single script from spawning thousands of fast-repeating callbacks that
    /// peg the main actor.
    private static let maxTimers = 64
    /// Floor on timer/timeout intervals (ms). Below this a tight repeating
    /// timer would starve the main actor.
    private static let minTimerIntervalMS = 50

    private weak var chatModel: ChatModel?
    private var cancellable: AnyCancellable?

    struct BotScript: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var name: String
        var enabled: Bool = true
        /// Relative filename under scriptsDir.
        var filename: String
        /// Hex-encoded SHA-256 of the most recently saved script source.
        /// Compared at load time so a tampered or partially-decrypted file
        /// can't silently execute. Optional for backwards compatibility
        /// with scripts written before this field existed.
        var contentHash: String? = nil
    }

    struct BotLogLine: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let level: Level
        let text: String
        enum Level { case info, error, script }
    }

    /// Per-script persistent key/value store backing the `irc.store` JS
    /// surface. Each script gets its own file at
    /// `scripts/<scriptID>.store.json`, encrypted at rest under the
    /// shared DEK once the keystore unlocks.
    let scriptStore: ScriptStore

    init(supportDir: URL) {
        let dir = supportDir.appendingPathComponent("scripts", isDirectory: true)
        self.scriptsDir = dir
        self.indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.scriptStore = ScriptStore(directory: dir)
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

    /// DEK pushed in by ChatModel whenever the keystore changes state. When
    /// non-nil, index.json AND every .js source file are wrapped with the
    /// shared envelope. Plaintext files keep loading because EncryptedJSON
    /// passes them through verbatim.
    private var currentKey: SymmetricKey?

    func setEncryptionKey(_ key: SymmetricKey?) {
        let changed = (key != nil) != (currentKey != nil)
        currentKey = key
        scriptStore.setEncryptionKey(key)
        if changed {
            // Newly-keyed: re-read so any encrypted index/script that was
            // unreadable a moment ago decodes now. Reseal the script
            // store too so a previously-plaintext write gets wrapped
            // under the new key without waiting for the next mutation.
            loadIndex()
            scriptStore.reseal()
            rebuildContext()
        }
    }

    private func loadIndex() {
        guard let raw = try? Data(contentsOf: indexURL) else {
            scripts = []
            return
        }
        guard let json = try? EncryptedJSON.unwrap(raw, key: currentKey),
              let decoded = try? JSONDecoder().decode([BotScript].self, from: json) else {
            // Encrypted index with no key yet → leave scripts empty until
            // setEncryptionKey rolls through.
            scripts = []
            return
        }
        scripts = decoded
    }

    private func saveIndex() {
        guard let plain = try? JSONEncoder().encode(scripts) else { return }
        _ = try? EncryptedJSON.safeWrite(plain, to: indexURL, key: currentKey)
    }

    func scriptSource(_ script: BotScript) -> String {
        let url = scriptsDir.appendingPathComponent(script.filename)
        guard let raw = try? Data(contentsOf: url) else { return "" }
        guard let plain = try? EncryptedJSON.unwrap(raw, key: currentKey) else { return "" }
        // Integrity check: refuse to return source whose SHA-256 doesn't
        // match the hash captured the last time we wrote the script.
        // Optional check (nil hash = grandfathered-in legacy script).
        if let expected = script.contentHash {
            let actual = Self.sha256Hex(plain)
            guard actual == expected else {
                appendLog(.error,
                          "Script \(script.name) rejected: content hash mismatch (expected \(expected.prefix(8))…, got \(actual.prefix(8))…). Reload after editing in Setup.")
                return ""
            }
        }
        return String(data: plain, encoding: .utf8) ?? ""
    }

    private func writeScript(_ script: inout BotScript, source: String) {
        let url = scriptsDir.appendingPathComponent(script.filename)
        let plain = Data(source.utf8)
        script.contentHash = Self.sha256Hex(plain)
        _ = try? EncryptedJSON.safeWrite(plain, to: url, key: currentKey)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func addScript(name: String, source: String) -> BotScript {
        let slug = fileSafe(name.isEmpty ? "script" : name)
        let rand = UUID().uuidString.prefix(6).lowercased()
        var s = BotScript(name: name.isEmpty ? "untitled" : name,
                          filename: "\(slug)-\(rand).js")
        writeScript(&s, source: source)
        scripts.append(s)
        saveIndex()
        rebuildContext()
        return s
    }

    func update(_ script: BotScript, name: String, source: String, enabled: Bool) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[i].name = name
        scripts[i].enabled = enabled
        writeScript(&scripts[i], source: source)
        saveIndex()
        rebuildContext()
    }

    func remove(_ script: BotScript) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        let url = scriptsDir.appendingPathComponent(scripts[i].filename)
        try? FileManager.default.removeItem(at: url)
        // Wipe the script's persistent store too — leaving orphan files
        // in scripts/ behind a removed script would leak both bytes and
        // (potentially) sensitive state.
        scriptStore.purge(scriptID: scripts[i].id)
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
        storeTokens.removeAll()

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
            guard !src.isEmpty else { continue }
            // Mint a fresh, opaque store token for this script and bake it
            // into its wrapper. The token (not the script UUID) is what the
            // store bridge trusts.
            let token = UUID().uuidString
            storeTokens[token] = s.id
            let wrapped = wrapScriptSource(src, storeToken: token)
            ctx.evaluateScript(wrapped, withSourceURL: URL(string: "purple-bot:///\(s.filename)"))
            appendLog(.info, "Loaded \(s.name)")
        }
        context = ctx
    }

    /// Reserve a timer id if we're under the global cap, else log and refuse.
    /// Returns nil when the cap is hit so the JS shim hands the script `0`.
    private func allocateTimerSlot() -> Int? {
        guard timers.count < Self.maxTimers else {
            appendLog(.error, "Timer limit (\(Self.maxTimers)) reached — ignoring setTimer/setTimeout. Clear timers you no longer need.")
            return nil
        }
        let id = nextTimerID
        nextTimerID += 1
        return id
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

        // irc.send(networkNameOrId, rawLine) — raw IRC line (single line only;
        // CR/LF/NUL are stripped at the wire seam to prevent command injection
        // from a sloppy or malicious script).
        let sendBlock: @convention(block) (String, String) -> Void = { [weak self] net, line in
            let safeNet  = IRCSanitize.field(net)
            let safeLine = IRCSanitize.line(line)
            guard !safeLine.isEmpty else { return }
            Task { @MainActor in self?.sendOnNetwork(name: safeNet, line: safeLine) }
        }
        irc.setObject(sendBlock, forKeyedSubscript: "send" as NSString)

        // irc.sendActive(rawLine)
        let sendActiveBlock: @convention(block) (String) -> Void = { [weak self] line in
            let safeLine = IRCSanitize.line(line)
            guard !safeLine.isEmpty else { return }
            Task { @MainActor in self?.sendOnActive(safeLine) }
        }
        irc.setObject(sendActiveBlock, forKeyedSubscript: "sendActive" as NSString)

        // irc.msg(target, text) — PRIVMSG on the active connection. Each
        // field is scrubbed for CR/LF/NUL before assembly so a multi-line
        // text collapses into a single PRIVMSG rather than smuggling a
        // second IRC command after the message body.
        let msgBlock: @convention(block) (String, String) -> Void = { [weak self] target, text in
            let safeTarget = IRCSanitize.field(target)
            let safeText   = IRCSanitize.field(text)
            guard !safeTarget.isEmpty, !safeText.isEmpty else { return }
            Task { @MainActor in
                self?.sendOnActive("PRIVMSG \(safeTarget) :\(safeText)")
            }
        }
        irc.setObject(msgBlock, forKeyedSubscript: "msg" as NSString)

        // irc.notice(target, text) — NOTICE on the active connection.
        let noticeBlock: @convention(block) (String, String) -> Void = { [weak self] target, text in
            let safeTarget = IRCSanitize.field(target)
            let safeText   = IRCSanitize.field(text)
            guard !safeTarget.isEmpty, !safeText.isEmpty else { return }
            Task { @MainActor in
                self?.sendOnActive("NOTICE \(safeTarget) :\(safeText)")
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
            guard let self, let id = self.allocateTimerSlot() else { return 0 }
            let interval = UInt64(max(Self.minTimerIntervalMS, ms)) * 1_000_000
            self.timers[id] = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: interval)
                    if Task.isCancelled { return }
                    cb.call(withArguments: [])
                }
            }
            return id
        }
        irc.setObject(setTimerBlock, forKeyedSubscript: "setTimer" as NSString)

        // irc.setTimeout(ms, cb) → id ; fires once.
        let setTimeoutBlock: @convention(block) (Int, JSValue) -> Int = { [weak self] ms, cb in
            guard let self, let id = self.allocateTimerSlot() else { return 0 }
            let interval = UInt64(max(Self.minTimerIntervalMS, ms)) * 1_000_000
            self.timers[id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: interval)
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

        // Per-script persistent store. Each script's source is wrapped in
        // an IIFE that synthesises a script-local `irc.store` object whose
        // four methods proxy to these underscore-prefixed Swift blocks with
        // the script's EPHEMERAL store TOKEN (not its UUID). The bridge
        // resolves the token to a store id via `storeTokens`; a token a
        // script didn't receive resolves to nothing, so one script can't
        // address another's store even if it learns the other's UUID. The
        // wrapper lives in `wrapScriptSource`. Behaviour on an unknown token
        // is a silent no-op.
        let storeGetBlock: @convention(block) (String, String) -> Any? = { [weak self] token, key in
            guard let self, let uuid = self.storeTokens[token] else { return nil }
            return self.scriptStore.get(scriptID: uuid, key: key)
        }
        irc.setObject(storeGetBlock, forKeyedSubscript: "_storeGet" as NSString)

        let storeSetBlock: @convention(block) (String, String, Any?) -> Void = { [weak self] token, key, value in
            guard let self, let uuid = self.storeTokens[token] else { return }
            self.scriptStore.set(scriptID: uuid, key: key, value: value)
        }
        irc.setObject(storeSetBlock, forKeyedSubscript: "_storeSet" as NSString)

        let storeDeleteBlock: @convention(block) (String, String) -> Void = { [weak self] token, key in
            guard let self, let uuid = self.storeTokens[token] else { return }
            self.scriptStore.delete(scriptID: uuid, key: key)
        }
        irc.setObject(storeDeleteBlock, forKeyedSubscript: "_storeDelete" as NSString)

        let storeKeysBlock: @convention(block) (String) -> [String] = { [weak self] token in
            guard let self, let uuid = self.storeTokens[token] else { return [] }
            return self.scriptStore.keys(scriptID: uuid)
        }
        irc.setObject(storeKeysBlock, forKeyedSubscript: "_storeKeys" as NSString)

        ctx.setObject(irc, forKeyedSubscript: "irc" as NSString)
    }

    /// Wrap a user script in an IIFE that hands it a per-script `irc`
    /// object with its store token baked in via the IIFE-local
    /// `__PURPLEBOT_TOKEN`. The wrapper makes `irc.store.get/set/delete/keys`
    /// route to the script's own JSON file without the script having to
    /// know its own id — and because the token is IIFE-local and minted
    /// fresh per rebuild, one script can't read another's token to reach
    /// its store. Top-level `var` declarations become IIFE-local — a tiny
    /// behaviour change from the previous bare `evaluateScript` path. Line
    /// numbers in exceptions shift by the prelude line count; the exception
    /// handler logs that line offset verbatim, so a stack trace at "line 3"
    /// inside a wrapped script maps to "line 1" of the user-visible source.
    private func wrapScriptSource(_ src: String, storeToken: String) -> String {
        return """
        (function() {
          'use strict';
          const __PURPLEBOT_TOKEN = '\(storeToken)';
          const irc = Object.assign({}, globalThis.irc, {
            store: {
              get: function(k) { return globalThis.irc._storeGet(__PURPLEBOT_TOKEN, k); },
              set: function(k, v) { globalThis.irc._storeSet(__PURPLEBOT_TOKEN, k, v); },
              delete: function(k) { globalThis.irc._storeDelete(__PURPLEBOT_TOKEN, k); },
              keys: function() { return globalThis.irc._storeKeys(__PURPLEBOT_TOKEN); }
            }
          });
        \(src)
        })();
        """
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
        case .watchedQueryAutoOpened(let bufferID, let from):
            return ("watchedQueryAutoOpened",
                    merge(["bufferID": bufferID.uuidString, "from": from]))
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
