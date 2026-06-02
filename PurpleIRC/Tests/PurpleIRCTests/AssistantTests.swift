import Foundation
import Testing
@testable import PurpleIRC

/// Coverage for the local-LLM assistant — the audit flagged the whole
/// subsystem as having zero tests. Focuses on the security-relevant URL
/// validation and the pure prompt-assembly / cleanup helpers (no network).
@Suite("Assistant")
struct AssistantTests {

    // MARK: - OllamaClient URL + local-host validation

    @Test func acceptsWellFormedLocalURLs() throws {
        // These should construct without throwing.
        _ = try OllamaClient(rawURL: "http://localhost:11434")
        _ = try OllamaClient(rawURL: "http://127.0.0.1:11434")
        _ = try OllamaClient(rawURL: "http://192.168.1.50:11434")  // LAN
        _ = try OllamaClient(rawURL: "http://10.0.0.9:11434")      // LAN
        _ = try OllamaClient(rawURL: "http://ollama.local:11434")  // mDNS
        _ = try OllamaClient(rawURL: "http://my-box:11434")        // single-label
    }

    @Test func rejectsMalformedURLs() {
        // No scheme — `localhost:11434` parses with scheme "localhost", host nil.
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "localhost:11434")
        }
        // Wrong scheme.
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "ftp://localhost:11434")
        }
        // Empty.
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "")
        }
    }

    @Test func rejectsNonLocalHosts() {
        // Public hostnames / routable IPs must be refused so private chat
        // content can't be POSTed off the machine.
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "http://evil.example.com:11434")
        }
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "https://api.openai.com")
        }
        #expect(throws: OllamaClient.Error.self) {
            _ = try OllamaClient(rawURL: "http://8.8.8.8:11434")
        }
    }

    @Test func isLocalHostClassification() {
        #expect(OllamaClient.isLocalHost("localhost"))
        #expect(OllamaClient.isLocalHost("127.0.0.1"))
        #expect(OllamaClient.isLocalHost("::1"))
        #expect(OllamaClient.isLocalHost("192.168.0.1"))
        #expect(OllamaClient.isLocalHost("172.16.5.5"))
        #expect(OllamaClient.isLocalHost("172.31.255.1"))
        #expect(OllamaClient.isLocalHost("nas.local"))
        #expect(!OllamaClient.isLocalHost("8.8.8.8"))
        #expect(!OllamaClient.isLocalHost("172.32.0.1"))   // just outside 172.16/12
        #expect(!OllamaClient.isLocalHost("example.com"))
    }

    // MARK: - cleanup()

    @Test func cleanupStripsLabelsAndQuotes() {
        #expect(AssistantEngine.cleanup("Assistant: hi there") == "hi there")
        #expect(AssistantEngine.cleanup("  \"wrapped reply\"  ") == "wrapped reply")
        #expect(AssistantEngine.cleanup("'single quoted'") == "single quoted")
        #expect(AssistantEngine.cleanup("plain reply") == "plain reply")
    }

    // MARK: - buildMessages()

    @Test func buildMessagesPrependsSystemAndMapsRoles() {
        let persona = AssistantPersona(name: "Tester", systemPrompt: "Be terse.")
        let lines: [ChatLine] = [
            ChatLine(timestamp: Date(), kind: .privmsg(nick: "alice", isSelf: false), text: "hey"),
            ChatLine(timestamp: Date(), kind: .join(nick: "bob"), text: ""),      // noise — skipped
            ChatLine(timestamp: Date(), kind: .privmsg(nick: "me", isSelf: true), text: "yo"),
        ]
        let msgs = AssistantEngine.buildMessages(persona: persona, lines: lines, contextLines: 10)
        #expect(msgs.first?.role == "system")
        #expect(msgs.first?.content == "Be terse.")
        let roles = msgs.dropFirst().map { $0.role }
        #expect(roles == ["user", "assistant"])   // join line skipped
    }
}
