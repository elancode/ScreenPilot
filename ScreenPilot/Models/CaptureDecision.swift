import Foundation

enum CaptureDecision: String, Codable {
    case captured
    case skippedIdle = "skipped_idle"
    case skippedNoDiff = "skipped_no_diff"
    case skippedBlocklist = "skipped_blocklist"
    case skippedBudget = "skipped_budget"
    case skippedBackoff = "skipped_backoff"
}
