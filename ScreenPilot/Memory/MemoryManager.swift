import Foundation

actor MemoryManager {

    private let writer = MemoryWriter()
    private let store = MemoryStore()
    private var maintenanceTask: Task<Void, Never>?

    private(set) var isEnabled: Bool = false

    private static let maintenanceInterval: TimeInterval = 1800
    private static let retentionDays = 90

    // MARK: - Lifecycle

    func initialize() async {
        isEnabled = true
        print("[ScreenPilot] Memory system enabled (FTS5)")
        startMaintenance()
    }

    func shutdown() async {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        await writer.flush()
    }

    // MARK: - Retrieval

    func retrieveMemory(activitySummary: String) async -> MemoryStore.MemoryContext {
        guard isEnabled else { return .empty }
        return await store.query(activitySummary: activitySummary)
    }

    // MARK: - Recording

    func recordActivity(_ entry: ActivityEntry) async {
        guard isEnabled else { return }
        await writer.writeActivity(entry)
    }

    func recordNudge(_ nudge: Nudge) async {
        guard isEnabled else { return }
        await writer.writeNudge(nudge)
    }

    func recordFeedback(nudge: Nudge, feedback: Nudge.Feedback) async {
        guard isEnabled else { return }
        await writer.updateNudgeFeedback(nudge, feedback: feedback)
    }

    // MARK: - Maintenance

    private func startMaintenance() {
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.maintenanceInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.performMaintenance()
            }
        }
    }

    private func performMaintenance() async {
        await writer.flush()
        do {
            try await Database.shared.deleteOldMemory(retentionDays: Self.retentionDays)
        } catch {
            print("[ScreenPilot] Memory cleanup failed: \(error.localizedDescription)")
        }
    }
}
