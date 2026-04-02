import Foundation
import CoreGraphics

@Observable
@MainActor
final class AppState {
    var isRunning: Bool = true
    var nudges: [Nudge] = []
    var unreadCount: Int = 0
    var currentActivity: String?
    var apiCallsToday: Int = 0
    var dailyBudgetLimit: Int = 500
    var selectedModel: String = "claude-sonnet-4-20250514"
    var customBlocklist: Set<String> = []

    // Follow-up query state
    var screenshotCache: [Int64: CGImage] = [:]
    var followUps: [Int64: [FollowUp]] = [:]
    var queryingNudgeId: Int64?
    var queryErrors: [Int64: String] = [:]

    /// Set by AppDelegate to wire up the analysis router
    var queryHandler: ((CGImage, Nudge, [FollowUp], String) async throws -> String)?

    var isBudgetExhausted: Bool {
        apiCallsToday >= dailyBudgetLimit
    }

    func addNudge(_ nudge: Nudge, screenshot: CGImage? = nil) {
        if let last = nudges.first, isSimilar(nudge, last) {
            // Skip duplicate nudge
            return
        }
        nudges.insert(nudge, at: 0)
        if let screenshot {
            screenshotCache[nudge.id] = screenshot
        }
        if nudges.count > 50 {
            let removed = nudges.removeLast()
            screenshotCache.removeValue(forKey: removed.id)
            followUps.removeValue(forKey: removed.id)
        }
        unreadCount += 1
    }

    private func isSimilar(_ a: Nudge, _ b: Nudge) -> Bool {
        let normalize: (String) -> String = { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        return normalize(a.title) == normalize(b.title)
            || normalize(a.body) == normalize(b.body)
    }

    func queryNudge(id: Int64, question: String) {
        guard let nudge = nudges.first(where: { $0.id == id }),
              let screenshot = screenshotCache[id],
              let handler = queryHandler else { return }

        queryingNudgeId = id
        queryErrors.removeValue(forKey: id)

        Task {
            do {
                let existing = followUps[id] ?? []
                let answer = try await handler(screenshot, nudge, existing, question)
                followUps[id, default: []].append(FollowUp(question: question, answer: answer))
            } catch {
                queryErrors[id] = error.localizedDescription
            }
            queryingNudgeId = nil
        }
    }

    func canQuery(nudgeId: Int64) -> Bool {
        screenshotCache[nudgeId] != nil
    }

    func markNudgeRead(_ id: Int64) {
        guard let index = nudges.firstIndex(where: { $0.id == id && !$0.isRead }) else { return }
        nudges[index].isRead = true
        unreadCount = max(0, unreadCount - 1)
    }

    func setFeedback(_ id: Int64, feedback: Nudge.Feedback) {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return }
        nudges[index].feedback = feedback
    }

    func resetDailyCounter() {
        apiCallsToday = 0
    }

    func loadSettings() async {
        do {
            if let model = try await Database.shared.getSetting(key: "model") {
                selectedModel = model
            }
            if let budget = try await Database.shared.getSetting(key: "dailyBudgetLimit"),
               let value = Int(budget) {
                dailyBudgetLimit = value
            }
            if let blocklist = try await Database.shared.getSetting(key: "customBlocklist") {
                customBlocklist = Set(
                    blocklist.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
            }
        } catch {
            print("[ScreenPilot] Failed to load settings: \(error.localizedDescription)")
        }
    }

    func saveSetting(key: String, value: String) {
        Task {
            do {
                try await Database.shared.setSetting(key: key, value: value)
            } catch {
                print("[ScreenPilot] Failed to save setting '\(key)': \(error.localizedDescription)")
            }
        }
    }
}
