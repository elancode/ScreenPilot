import Foundation

actor ContextWindow {
    private var entries: [ActivityEntry] = []
    private let maxEntries = 50

    struct NudgeEntry {
        let title: String
        let body: String
    }

    private var recentNudgeEntries: [NudgeEntry] = []
    private let maxNudgeEntries = 15

    func append(entry: ActivityEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }

    func appendNudge(title: String, body: String) {
        recentNudgeEntries.append(NudgeEntry(title: title, body: body))
        if recentNudgeEntries.count > maxNudgeEntries {
            recentNudgeEntries.removeFirst()
        }
    }

    func recentEntries(count: Int = 10) -> [String] {
        entries.suffix(count).map { entry in
            "[\(entry.timestamp.formatted(.relative(presentation: .named)))] " +
            "[\(entry.app)] \(entry.summary)"
        }
    }

    func recentNudges(count: Int = 10) -> [NudgeEntry] {
        Array(recentNudgeEntries.suffix(count))
    }

    func clear() {
        entries.removeAll()
        recentNudgeEntries.removeAll()
    }
}
