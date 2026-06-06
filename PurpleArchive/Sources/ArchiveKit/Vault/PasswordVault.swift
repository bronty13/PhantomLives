import Foundation
import Security

/// Remembers archive passwords so the user types them once. Keyed by a stable
/// archive identity (filename — survives the archive moving between folders).
/// The GUI auto-fills from here; `parc --use-vault` reads the same store.
public protocol PasswordVault: Sendable {
    func password(for key: String) -> String?
    func setPassword(_ password: String, for key: String)
    func removePassword(for key: String)
    func storedKeys() -> [String]
}

public extension PasswordVault {
    /// Derive the vault key for an archive URL. Filename-based so a remembered
    /// password keeps working when the archive is moved or re-downloaded.
    func key(for url: URL) -> String { url.lastPathComponent }

    func password(for url: URL) -> String? { password(for: key(for: url)) }
    func setPassword(_ p: String, for url: URL) { setPassword(p, for: key(for: url)) }
    func removePassword(for url: URL) { removePassword(for: key(for: url)) }
}

/// macOS Keychain-backed vault (generic-password items under a single service).
public struct KeychainVault: PasswordVault {
    public let service: String

    public init(service: String = "com.bronty13.PurpleArchive.vault") {
        self.service = service
    }

    public func password(for key: String) -> String? {
        var query = baseQuery(account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String, for key: String) {
        let data = Data(password.utf8)
        let base = baseQuery(account: key)
        // Update if present, else add.
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func removePassword(for key: String) {
        SecItemDelete(baseQuery(account: key) as CFDictionary)
    }

    public func storedKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let array = items as? [[String: Any]] else { return [] }
        return array.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// In-memory vault — the fallback when the Keychain is unavailable (headless
/// CI) and the backing store for unit tests.
public final class InMemoryVault: PasswordVault, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func password(for key: String) -> String? { lock.withLock { store[key] } }
    public func setPassword(_ password: String, for key: String) { lock.withLock { store[key] = password } }
    public func removePassword(for key: String) { lock.withLock { _ = store.removeValue(forKey: key) } }
    public func storedKeys() -> [String] { lock.withLock { store.keys.sorted() } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
