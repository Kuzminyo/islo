import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
}

/// A small to-do list kept in the island.
final class TaskList: ObservableObject {
    private static let key = "tasks"

    @Published private(set) var items: [TaskItem] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) {
            items = saved
        }
    }

    var doneCount: Int { items.filter(\.isDone).count }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.append(TaskItem(title: title))
        save()
    }

    func toggle(_ item: TaskItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isDone.toggle()
        save()
    }

    func remove(_ item: TaskItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeDone() {
        items.removeAll(where: \.isDone)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
