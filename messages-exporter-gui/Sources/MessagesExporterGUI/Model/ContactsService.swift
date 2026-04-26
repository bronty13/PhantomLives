import Foundation
import Contacts

/// Wraps CNContactStore for autocompleting the contact name field. Pure
/// UX nicety — the underlying CLI walks AddressBook on its own, so if
/// the user denies Contacts permission the GUI just silently skips
/// suggestions and the export still works (the typed name is passed
/// straight to the CLI's fuzzy matcher).
///
/// The autocomplete query (`suggestions(for:)`) is `nonisolated async`
/// and dispatches to a detached Task so a slow AddressBook lookup never
/// stalls the main thread. Permission state remains main-actor-isolated
/// so SwiftUI bindings work without warnings.
@MainActor
final class ContactsService: ObservableObject {

    @Published private(set) var permissionDenied = false

    private let store = CNContactStore()

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

    /// Returns up to `limit` display names matching `prefix`. Runs the
    /// AddressBook query off the main actor — `CNContactStore` is
    /// documented as thread-safe and `unifiedContacts(matching:)` is a
    /// blocking call that can take meaningful time on large books.
    nonisolated func suggestions(for prefix: String, limit: Int = 8) async -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        let denied = await self.permissionDenied
        guard !denied else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey      as CNKeyDescriptor,
                CNContactFamilyNameKey     as CNKeyDescriptor,
                CNContactNicknameKey       as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor
            ]
            let predicate = CNContact.predicateForContacts(matchingName: trimmed)
            let detachedStore = CNContactStore()
            guard let contacts = try? detachedStore.unifiedContacts(
                matching: predicate, keysToFetch: keys) else {
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
        }.value
    }
}

/// Free function so the detached Task above doesn't have to capture the
/// (main-actor-isolated) ContactsService instance.
private func candidateNames(for c: CNContact) -> [String] {
    var out: [String] = []
    let full = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
    if !full.isEmpty { out.append(full) }
    if !c.nickname.isEmpty { out.append(c.nickname) }
    if !c.givenName.isEmpty && !out.contains(c.givenName) { out.append(c.givenName) }
    if !c.organizationName.isEmpty && full.isEmpty { out.append(c.organizationName) }
    return out
}
