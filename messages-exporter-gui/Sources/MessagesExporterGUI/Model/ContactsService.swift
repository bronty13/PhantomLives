import Foundation
import Contacts

/// Wraps CNContactStore for autocompleting the contact name field. Pure
/// UX nicety — the underlying CLI walks AddressBook on its own, so if
/// the user denies Contacts permission the GUI just silently skips
/// suggestions and the export still works (the typed name is passed
/// straight to the CLI's fuzzy matcher).
@MainActor
final class ContactsService: ObservableObject {

    @Published private(set) var permissionDenied = false

    private let store = CNContactStore()
    private let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor
    ]

    func requestAccessIfNeeded() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.permissionDenied = !granted
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        default:
            permissionDenied = false
        }
    }

    /// Returns up to `limit` display names matching `prefix`. Returns
    /// empty when permission is missing or the prefix is too short to
    /// be useful.
    func suggestions(for prefix: String, limit: Int = 8) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, !permissionDenied else { return [] }

        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch) else {
            return []
        }
        var names: [String] = []
        var seen = Set<String>()
        for c in contacts {
            for candidate in candidateNames(for: c) where !seen.contains(candidate) {
                names.append(candidate)
                seen.insert(candidate)
                if names.count >= limit { return names }
            }
        }
        return names
    }

    private func candidateNames(for c: CNContact) -> [String] {
        var out: [String] = []
        let full = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { out.append(full) }
        if !c.nickname.isEmpty { out.append(c.nickname) }
        if !c.givenName.isEmpty && !out.contains(c.givenName) { out.append(c.givenName) }
        if !c.organizationName.isEmpty && full.isEmpty { out.append(c.organizationName) }
        return out
    }
}
