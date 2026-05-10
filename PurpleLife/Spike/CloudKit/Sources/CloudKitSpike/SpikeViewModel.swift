import CloudKit
import Foundation
import SwiftUI

@MainActor
final class SpikeViewModel: ObservableObject {
    static let containerID = "iCloud.com.bronty13.PurpleLife"

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: String
        let message: String
    }

    struct SpikeResult {
        let passed: Bool
    }

    @Published var log: [LogEntry] = []
    @Published var isRunning = false
    @Published var result: SpikeResult?

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func runSpike() async {
        isRunning = true
        result = nil
        log.removeAll()
        defer { isRunning = false }

        do {
            let container = CKContainer(identifier: Self.containerID)
            let database = container.privateCloudDatabase

            try await ensureAccount(container: container)

            // Toy schema: a single CKRecord type "PurpleObject" carrying:
            //   - typed plaintext columns: type, parent, createdAt, updatedAt
            //   - encryptedValues["fieldsJSON"]: opaque JSON blob the user
            //     never wants Apple to be able to read.
            let recordID = CKRecord.ID(recordName: "spike-\(UUID().uuidString)")
            let record = CKRecord(recordType: "PurpleObject", recordID: recordID)

            let now = Date()
            record["type"] = "Person" as CKRecordValue
            record["createdAt"] = now as CKRecordValue
            record["updatedAt"] = now as CKRecordValue

            let secretFields: [String: Any] = [
                "displayName": "Ada Lovelace",
                "email": "ada@example.test",
                "notes": "Spike payload — must round-trip byte-for-byte.",
                "tags": ["friend", "math"],
                "weightLbs": 130
            ]
            let payload = try JSONSerialization.data(
                withJSONObject: secretFields, options: [.sortedKeys]
            )
            record.encryptedValues["fieldsJSON"] = payload as CKRecordValue
            let payloadHash = sha256(payload)

            append("save: posting record \(recordID.recordName)")
            append("save: payload \(payload.count) bytes, sha256=\(payloadHash.prefix(16))…")
            let saved = try await database.save(record)
            append("save: ok — modificationDate \(saved.modificationDate?.description ?? "nil")")

            append("fetch: requesting record by ID")
            let fetched = try await database.record(for: recordID)
            append("fetch: ok — recordChangeTag \(fetched.recordChangeTag ?? "nil")")

            // Verify plaintext columns survived.
            let typeOK = (fetched["type"] as? String) == "Person"
            append("verify: plaintext type column round-tripped: \(typeOK ? "yes" : "NO")")

            // Verify the encrypted blob came back identical.
            guard let returnedData = fetched.encryptedValues["fieldsJSON"] as? Data else {
                append("verify: FAIL — encryptedValues[fieldsJSON] not a Data")
                result = SpikeResult(passed: false)
                return
            }
            let returnedHash = sha256(returnedData)
            let bytesMatch = returnedData == payload
            append("verify: returned \(returnedData.count) bytes, sha256=\(returnedHash.prefix(16))…")
            append("verify: byte-for-byte match: \(bytesMatch ? "yes" : "NO")")

            // Optional cleanup so the dev container doesn't accumulate cruft.
            append("cleanup: deleting test record")
            _ = try await database.deleteRecord(withID: recordID)
            append("cleanup: ok")

            let passed = typeOK && bytesMatch
            append(passed ? "RESULT: PASS" : "RESULT: FAIL")
            result = SpikeResult(passed: passed)
        } catch {
            append("ERROR: \(error.localizedDescription)")
            if let ck = error as? CKError {
                append("CKError.code = \(ck.code.rawValue) (\(ck.errorCode))")
            }
            result = SpikeResult(passed: false)
        }
    }

    private func ensureAccount(container: CKContainer) async throws {
        let status = try await container.accountStatus()
        switch status {
        case .available:
            append("account: iCloud available")
        case .noAccount:
            append("account: NO ACCOUNT — sign in to iCloud in System Settings")
            throw CKError(.notAuthenticated)
        case .restricted:
            append("account: RESTRICTED")
            throw CKError(.notAuthenticated)
        case .couldNotDetermine:
            append("account: could not determine — check network")
            throw CKError(.networkUnavailable)
        case .temporarilyUnavailable:
            append("account: temporarily unavailable")
            throw CKError(.networkUnavailable)
        @unknown default:
            append("account: unknown status (\(status.rawValue))")
            throw CKError(.internalError)
        }
    }

    private func append(_ message: String) {
        let stamp = formatter.string(from: Date())
        log.append(LogEntry(timestamp: stamp, message: message))
    }

    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buf in
            _ = CC_SHA256_FALLBACK(buf.baseAddress, CC_LONG(buf.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// Lightweight SHA-256 wrapper without importing CommonCrypto's bridging
// header. CryptoKit gives us this directly on macOS 10.15+.
import CryptoKit

@inline(__always)
private func CC_SHA256_FALLBACK(
    _ data: UnsafeRawPointer?, _ len: UInt32, _ md: UnsafeMutablePointer<UInt8>
) -> UnsafeMutablePointer<UInt8>? {
    guard let data else { return nil }
    let bytes = UnsafeRawBufferPointer(start: data, count: Int(len))
    let digest = SHA256.hash(data: Data(bytes))
    for (i, b) in digest.enumerated() {
        md[i] = b
    }
    return md
}

private typealias CC_LONG = UInt32
