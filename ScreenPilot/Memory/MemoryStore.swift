import Foundation

actor MemoryStore {

    struct MemoryContext {
        let entries: [String]
        let isEmpty: Bool

        static let empty = MemoryContext(entries: [], isEmpty: true)
    }

    private var cachedQuery: String?
    private var cachedResult: MemoryContext?
    private var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 30

    private static let maxTokenBudget = 500
    private static let approxCharsPerToken = 4

    func query(activitySummary: String) async -> MemoryContext {
        if let cached = cachedResult,
           cachedQuery == activitySummary,
           Date.now.timeIntervalSince(cacheTimestamp) < Self.cacheTTL {
            return cached
        }

        do {
            let records = try await Database.shared.searchMemory(query: activitySummary, limit: 5)

            guard !records.isEmpty else {
                return cacheAndReturn(.empty, for: activitySummary)
            }

            let formatted = formatRecords(records)
            let context = MemoryContext(entries: formatted, isEmpty: formatted.isEmpty)
            return cacheAndReturn(context, for: activitySummary)
        } catch {
            print("[ScreenPilot] Memory query failed: \(error.localizedDescription)")
            return cacheAndReturn(.empty, for: activitySummary)
        }
    }

    // MARK: - Private

    private func formatRecords(_ records: [Database.MemoryRecord]) -> [String] {
        var entries: [String] = []
        var totalChars = 0
        let charBudget = Self.maxTokenBudget * Self.approxCharsPerToken
        let isoFormatter = ISO8601DateFormatter()

        for record in records {
            let relative: String
            if let date = isoFormatter.date(from: record.timestamp) {
                relative = date.formatted(.relative(presentation: .named))
            } else {
                relative = record.timestamp
            }

            let typeLabel = record.type == "nudge" ? "[Past nudge]" : "[Past activity]"
            let feedbackNote = record.feedback == "positive" ? " (user found this helpful)" : ""
            let entry = "- \(typeLabel) [\(relative)] \(record.content)\(feedbackNote)"

            if totalChars + entry.count > charBudget { break }
            totalChars += entry.count
            entries.append(entry)
        }

        return entries
    }

    private func cacheAndReturn(_ context: MemoryContext, for query: String) -> MemoryContext {
        cachedQuery = query
        cachedResult = context
        cacheTimestamp = .now
        return context
    }
}
