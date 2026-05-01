import Foundation

actor MemoryWriter {

    private var activityBuffer: [ActivityEntry] = []
    private var currentSessionApp: String?
    private var currentSessionStart: Date?
    private var flushTask: Task<Void, Never>?

    private static let flushInterval: TimeInterval = 60
    private static let maxBufferSize = 10
    private static let sessionGap: TimeInterval = 600

    // MARK: - Public

    func writeActivity(_ entry: ActivityEntry) async {
        let isNewSession = currentSessionApp != entry.app ||
            (currentSessionStart.map { entry.timestamp.timeIntervalSince($0) > Self.sessionGap } ?? true)

        if isNewSession && !activityBuffer.isEmpty {
            await flushActivityBuffer()
        }

        if isNewSession {
            currentSessionApp = entry.app
            currentSessionStart = entry.timestamp
        }

        activityBuffer.append(entry)

        if activityBuffer.count >= Self.maxBufferSize {
            await flushActivityBuffer()
        }

        scheduleFlush()
    }

    func writeNudge(_ nudge: Nudge) async {
        do {
            try await Database.shared.insertMemory(
                type: "nudge",
                app: nudge.activitySummary ?? "",
                title: nudge.title,
                content: nudge.body,
                timestamp: nudge.timestamp
            )
        } catch {
            print("[ScreenPilot] Memory write nudge failed: \(error.localizedDescription)")
        }
    }

    func updateNudgeFeedback(_ nudge: Nudge, feedback: Nudge.Feedback) async {
        do {
            try await Database.shared.updateMemoryFeedback(
                title: nudge.title,
                feedback: feedback.rawValue
            )
        } catch {
            print("[ScreenPilot] Memory update feedback failed: \(error.localizedDescription)")
        }
    }

    func flush() async {
        if !activityBuffer.isEmpty {
            await flushActivityBuffer()
        }
    }

    // MARK: - Private

    private func flushActivityBuffer() async {
        guard !activityBuffer.isEmpty else { return }

        let entries = activityBuffer
        let app = currentSessionApp ?? "Unknown"
        let start = entries.first!.timestamp

        let summaries = entries.map { $0.summary }
        let windowTitles = entries.compactMap { $0.windowTitle }.uniqued()

        let title = "\(app) session"
        var content = summaries.joined(separator: ". ")
        if !windowTitles.isEmpty {
            content += " | Windows: " + windowTitles.joined(separator: ", ")
        }

        do {
            try await Database.shared.insertMemory(
                type: "activity",
                app: app,
                title: title,
                content: content,
                timestamp: start
            )
        } catch {
            print("[ScreenPilot] Memory write activity failed: \(error.localizedDescription)")
        }

        activityBuffer.removeAll()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.flushInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
