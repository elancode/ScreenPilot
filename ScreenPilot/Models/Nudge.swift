import Foundation

enum NudgeType: String, Codable {
    case technicalCopilot = "technical_copilot"
    case taskAssistant = "task_assistant"
}

struct Nudge: Identifiable, Codable {
    let id: Int64
    let timestamp: Date
    let type: NudgeType
    let title: String
    let body: String
    let activitySummary: String?
    var feedback: Feedback?
    var isRead: Bool

    enum Feedback: String, Codable {
        case positive, negative
    }
}
