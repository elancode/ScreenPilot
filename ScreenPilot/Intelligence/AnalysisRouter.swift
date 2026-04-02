import Foundation
import CoreGraphics

actor AnalysisRouter {
    private let llmClient: LLMClient
    private let contextWindow: ContextWindow
    private let appState: AppState

    init(llmClient: LLMClient, contextWindow: ContextWindow, appState: AppState) {
        self.llmClient = llmClient
        self.contextWindow = contextWindow
        self.appState = appState
    }

    func analyze(image: CGImage, appName: String, windowTitle: String) async -> AnalysisResult? {
        let contextHistory = await contextWindow.recentEntries(count: 10)
        let model = await MainActor.run { appState.selectedModel }

        let request = LLMClient.AnalysisRequest(
            image: image,
            systemPrompt: AnalysisPrompts.combined,
            contextHistory: contextHistory,
            model: model
        )

        do {
            let response = try await callWithBackoff { [llmClient] in
                try await llmClient.analyze(request)
            }

            guard let parsed = NudgeParser.parse(response.rawText) else {
                return AnalysisResult(activitySummary: "Unable to parse response", nudge: nil)
            }

            await contextWindow.append(entry: ActivityEntry(
                timestamp: .now,
                app: appName,
                bundleId: nil,
                windowTitle: windowTitle,
                summary: parsed.activitySummary
            ))

            return AnalysisResult(
                activitySummary: parsed.activitySummary,
                nudge: parsed.nudge
            )
        } catch {
            print("[ScreenPilot] Analysis error: \(error.localizedDescription)")
            return nil
        }
    }

    func followUp(
        image: CGImage,
        nudge: Nudge,
        previousFollowUps: [FollowUp],
        question: String
    ) async throws -> String {
        let model = await MainActor.run { appState.selectedModel }

        let request = LLMClient.FollowUpRequest(
            image: image,
            systemPrompt: AnalysisPrompts.followUp(nudgeTitle: nudge.title, nudgeBody: nudge.body),
            conversationHistory: previousFollowUps.map { ($0.question, $0.answer) },
            question: question,
            model: model
        )

        let response = try await callWithBackoff { [llmClient] in
            try await llmClient.followUp(request)
        }

        await MainActor.run { appState.apiCallsToday += 1 }

        return response.rawText
    }

    // MARK: - Retry with Backoff

    private func callWithBackoff<T>(
        maxRetries: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var delay: TimeInterval = 1.0
        var lastError: Error?

        for _ in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, 30)
            }
        }
        throw lastError!
    }
}
