import Foundation
import CoreGraphics

actor AnalysisRouter {
    private let llmClient: LLMClient
    private let contextWindow: ContextWindow
    private let appState: AppState
    private let memoryManager: MemoryManager?

    init(llmClient: LLMClient, contextWindow: ContextWindow, appState: AppState, memoryManager: MemoryManager? = nil) {
        self.llmClient = llmClient
        self.contextWindow = contextWindow
        self.appState = appState
        self.memoryManager = memoryManager
    }

    func analyze(image: CGImage, appName: String, windowTitle: String) async -> AnalysisResult? {
        let contextHistory = await contextWindow.recentEntries(count: 10)
        let recentNudges = await contextWindow.recentNudges(count: 10)
        let model = await MainActor.run { appState.selectedModel }

        // === Pass 1: Screenshot analysis ===
        let request = LLMClient.AnalysisRequest(
            image: image,
            systemPrompt: AnalysisPrompts.combined,
            contextHistory: contextHistory,
            recentNudges: recentNudges,
            model: model
        )

        do {
            let response = try await callWithBackoff { [llmClient] in
                try await llmClient.analyze(request)
            }

            guard let parsed = NudgeParser.parse(response.rawText) else {
                return AnalysisResult(activitySummary: "Unable to parse response", nudge: nil)
            }

            let entry = ActivityEntry(
                timestamp: .now,
                app: appName,
                bundleId: nil,
                windowTitle: windowTitle,
                summary: parsed.activitySummary
            )

            await contextWindow.append(entry: entry)

            if let nudge = parsed.nudge {
                await contextWindow.appendNudge(title: nudge.title, body: nudge.body)
            }

            // === Memory: query + conditional pass 2 ===
            var finalNudge = parsed.nudge

            if let nudge = parsed.nudge, let memoryManager, await memoryManager.isEnabled {
                let memory = await memoryManager.retrieveMemory(
                    activitySummary: parsed.activitySummary
                )

                if !memory.isEmpty {
                    let enriched = try? await callWithBackoff { [llmClient] in
                        try await llmClient.enrich(LLMClient.EnrichmentRequest(
                            nudge: nudge,
                            activitySummary: parsed.activitySummary,
                            memoryContext: memory.entries,
                            model: model
                        ))
                    }
                    if let enriched {
                        finalNudge = enriched
                    }
                }
            }

            // Record to long-term memory
            await memoryManager?.recordActivity(entry)
            if let nudge = finalNudge {
                await memoryManager?.recordNudge(nudge)
            }

            return AnalysisResult(
                activitySummary: parsed.activitySummary,
                nudge: finalNudge
            )
        } catch {
            print("[ScreenPilot] Analysis error: \(error.localizedDescription)")
            return AnalysisResult(activitySummary: "", nudge: nil, error: error.localizedDescription)
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
