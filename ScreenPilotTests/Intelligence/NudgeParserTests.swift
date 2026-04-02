import XCTest
@testable import ScreenPilot

final class NudgeParserTests: XCTestCase {

    // MARK: - Valid JSON

    func test_validCombinedResponse_withNudge() {
        let json = """
        {
          "activity_summary": "User is configuring IAM policies in AWS Console",
          "nudge_type": "technical_copilot",
          "title": "IAM policy is overly permissive",
          "body": "The policy grants * on all resources. Scope to specific ARNs."
        }
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.activitySummary, "User is configuring IAM policies in AWS Console")
        XCTAssertNotNil(result?.nudge)
        XCTAssertEqual(result?.nudge?.type, .technicalCopilot)
        XCTAssertEqual(result?.nudge?.title, "IAM policy is overly permissive")
    }

    func test_validCombinedResponse_noNudge() {
        let json = """
        {
          "activity_summary": "User is reading documentation",
          "nudge_type": "none",
          "title": null,
          "body": null
        }
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.activitySummary, "User is reading documentation")
        XCTAssertNil(result?.nudge)
    }

    func test_taskAssistantNudge() {
        let json = """
        {
          "activity_summary": "User is writing a PR review",
          "nudge_type": "task_assistant",
          "title": "PR review draft",
          "body": "LGTM overall. A few suggestions:\\n1. Consider using a guard clause..."
        }
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result?.nudge)
        XCTAssertEqual(result?.nudge?.type, .taskAssistant)
    }

    // MARK: - Markdown Fences

    func test_jsonWrappedInMarkdownFences() {
        let json = """
        ```json
        {
          "activity_summary": "User is browsing",
          "nudge_type": "none",
          "title": null,
          "body": null
        }
        ```
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.activitySummary, "User is browsing")
    }

    func test_jsonWrappedInPlainFences() {
        let json = """
        ```
        {
          "activity_summary": "User is coding",
          "nudge_type": "none",
          "title": null,
          "body": null
        }
        ```
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result)
    }

    // MARK: - Malformed Input

    func test_malformedJSON_returnsNil() {
        let json = "this is not json at all"
        XCTAssertNil(NudgeParser.parse(json))
    }

    func test_emptyString_returnsNil() {
        XCTAssertNil(NudgeParser.parse(""))
    }

    func test_incompleteJSON_returnsNil() {
        let json = """
        { "activity_summary": "test"
        """
        XCTAssertNil(NudgeParser.parse(json))
    }

    // MARK: - Sanitization

    func test_scriptTagsSanitized() {
        let json = """
        {
          "activity_summary": "User is working",
          "nudge_type": "technical_copilot",
          "title": "XSS test",
          "body": "<script>alert('xss')</script>"
        }
        """

        let result = NudgeParser.parse(json)
        XCTAssertNotNil(result?.nudge)
        XCTAssertFalse(result?.nudge?.body.contains("<script") ?? true)
    }
}
