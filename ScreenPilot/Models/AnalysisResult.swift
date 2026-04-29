import Foundation

struct AnalysisResult {
    let activitySummary: String
    let nudge: Nudge?
    let error: String?

    init(activitySummary: String, nudge: Nudge?, error: String? = nil) {
        self.activitySummary = activitySummary
        self.nudge = nudge
        self.error = error
    }
}
