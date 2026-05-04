import Testing
import Foundation
@testable import SizzleBot

@Suite("Message model")
struct MessageTests {

    @Test("Default initializer generates unique IDs")
    func uniqueIds() {
        let a = Message(role: .user, content: "hello")
        let b = Message(role: .user, content: "hello")
        #expect(a.id != b.id)
    }

    @Test("Role encodes and decodes as raw string")
    func roleCodable() throws {
        let msg = Message(role: .assistant, content: "Hi there!")
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["role"] as? String == "assistant")
    }

    @Test("All role cases are representable")
    func allRoles() {
        let roles: [Message.Role] = [.user, .assistant, .system]
        for role in roles {
            let msg = Message(role: role, content: "test")
            #expect(msg.role == role)
        }
    }

    @Test("Encoding and decoding round-trips content and timestamp")
    func codableRoundTrip() throws {
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Message(role: .user, content: "Round-trip test", timestamp: ts)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Round-trip test")
        #expect(abs(decoded.timestamp.timeIntervalSince(ts)) < 0.001)
    }

    @Test("Content is stored verbatim including whitespace")
    func contentPreservesWhitespace() {
        let content = "  hello\n\nworld  "
        let msg = Message(role: .assistant, content: content)
        #expect(msg.content == content)
    }

    @Test("Default initializer leaves images nil")
    func imagesDefaultNil() {
        let msg = Message(role: .user, content: "no image")
        #expect(msg.images == nil)
    }

    @Test("Images round-trip through Codable")
    func imagesCodableRoundTrip() throws {
        let images = ["AAAAaaaaBBBB==", "CCCCccccDDDD=="]
        let original = Message(role: .user, content: "describe", images: images)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.images == images)
    }

    @Test("Pre-1.3 Message JSON without images field decodes with nil images")
    func backwardCompatNoImagesField() throws {
        let legacyJSON = """
        {
          "id": "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
          "role": "user",
          "content": "older message",
          "timestamp": 770000000.0
        }
        """
        let decoded = try JSONDecoder().decode(Message.self, from: legacyJSON.data(using: .utf8)!)
        #expect(decoded.images == nil)
        #expect(decoded.content == "older message")
    }
}
