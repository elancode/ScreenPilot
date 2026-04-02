import Foundation

actor ContextWindow {
    private var entries: [ActivityEntry] = []
    private let maxEntries = 50

    func append(entry: ActivityEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }

    func recentEntries(count: Int = 10) -> [String] {
        entries.suffix(count).map { entry in
            "[\(entry.timestamp.formatted(.relative(presentation: .named)))] " +
            "[\(entry.app)] \(entry.summary)"
        }
    }

    func clear() {
        entries.removeAll()
    }
}
