import AppKit

/// Files parked in the island for a moment, to drag somewhere else later.
/// Only references are kept; the files stay where they are.
final class Shelf: ObservableObject {
    private static let key = "shelfFiles"

    @Published private(set) var files: [URL] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        files = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { url in !files.contains(url) }
        guard !new.isEmpty else { return }
        files.append(contentsOf: new)
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files.removeAll()
        save()
    }

    func airDrop() {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else { return }
        NSApp.activate()
        service.perform(withItems: files)
    }

    private func save() {
        UserDefaults.standard.set(files.map(\.path), forKey: Self.key)
    }
}
