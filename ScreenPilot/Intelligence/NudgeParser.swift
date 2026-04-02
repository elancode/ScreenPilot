import Foundation

struct NudgeParser {
    /// Parse the LLM's JSON response into a Nudge.
    /// Returns nil if nudge_type is "none" or parsing fails.
    static func parse(_ response: String) -> (activitySummary: String, nudge: Nudge?)? {
        let cleaned = stripMarkdownFences(response)

        guard let data = cleaned.data(using: .utf8) else { return nil }

        // Try combined prompt format
        if let combined = try? JSONDecoder().decode(CombinedResponse.self, from: data) {
            let nudge: Nudge?
            if let nudgeType = NudgeType(rawValue: combined.nudgeType),
               let title = combined.title,
               let body = combined.body {
                nudge = Nudge(
                    id: Int64(Date.now.timeIntervalSince1970 * 1000),
                    timestamp: .now,
                    type: nudgeType,
                    title: sanitize(title),
                    body: sanitize(body),
                    activitySummary: combined.activitySummary,
                    feedback: nil,
                    isRead: false
                )
            } else {
                nudge = nil
            }
            return (combined.activitySummary, nudge)
        }

        return nil
    }

    // MARK: - Private

    private static func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.hasPrefix("```json") {
            result = String(result.dropFirst(7))
        } else if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
        }

        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "<script", with: "&lt;script", options: .caseInsensitive)
            .replacingOccurrences(of: "javascript:", with: "", options: .caseInsensitive)
    }
}

// MARK: - Response Models

private struct CombinedResponse: Decodable {
    let activitySummary: String
    let nudgeType: String
    let title: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case activitySummary = "activity_summary"
        case nudgeType = "nudge_type"
        case title
        case body
    }
}

private enum NoneType: String, Decodable {
    case none
}
