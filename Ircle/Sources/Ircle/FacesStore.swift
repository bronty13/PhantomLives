import Foundation
import AppKit

/// Persists user "faces" — locally-assigned avatar images keyed by nick. The
/// classic Ircle Faces window showed a picture per user; this is the modern,
/// clean-room take: the user assigns an image to a nick (no network art), and
/// nicks without one get a generated monogram (see `FaceGraphics`).
///
/// Storage: `<base>/faces.json` maps folded-nick → filename inside `<base>/Faces/`.
/// Since `<base>` is Application Support, faces ride along in the launch backup.
@MainActor
final class FacesStore: ObservableObject {
    /// folded nick → image filename within `facesDir`.
    @Published private(set) var assignments: [String: String] = [:]

    private let baseDir: URL
    private var facesDir: URL { baseDir.appendingPathComponent("Faces", isDirectory: true) }
    private var indexURL: URL { baseDir.appendingPathComponent("faces.json") }

    /// `baseDir` is the app-support directory (tests pass a temp dir).
    init(baseDir: URL) {
        self.baseDir = baseDir
        load()
    }

    func hasImage(for nick: String) -> Bool {
        assignments[IRCCase.fold(nick)] != nil
    }

    /// Loaded NSImage for a nick's assigned face, or nil if none/unreadable.
    func image(for nick: String) -> NSImage? {
        guard let file = assignments[IRCCase.fold(nick)] else { return nil }
        let url = facesDir.appendingPathComponent(file)
        return NSImage(contentsOf: url)
    }

    /// Copy `imageURL` into the faces directory and assign it to `nick`. Any
    /// previously-assigned file for that nick is removed.
    @discardableResult
    func assign(imageAt imageURL: URL, to nick: String) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: facesDir, withIntermediateDirectories: true)
        let folded = IRCCase.fold(nick)
        let ext = imageURL.pathExtension.isEmpty ? "png" : imageURL.pathExtension
        let filename = "\(folded)-\(UUID().uuidString).\(ext)"
        let dest = facesDir.appendingPathComponent(filename)
        try fm.copyItem(at: imageURL, to: dest)
        // Remove the prior file for this nick, if any.
        if let old = assignments[folded] {
            try? fm.removeItem(at: facesDir.appendingPathComponent(old))
        }
        assignments[folded] = filename
        save()
        return filename
    }

    /// Remove a nick's assigned face (deletes the file too).
    func clear(_ nick: String) {
        let folded = IRCCase.fold(nick)
        if let file = assignments[folded] {
            try? FileManager.default.removeItem(at: facesDir.appendingPathComponent(file))
        }
        assignments[folded] = nil
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        assignments = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
