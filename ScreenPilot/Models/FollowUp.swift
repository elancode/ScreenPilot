import Foundation

struct FollowUp: Identifiable {
    let id: UUID
    let question: String
    let answer: String
    let timestamp: Date

    init(question: String, answer: String) {
        self.id = UUID()
        self.question = question
        self.answer = answer
        self.timestamp = .now
    }
}
