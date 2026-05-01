import SwiftUI

struct NudgeFeedView: View {
    @Bindable var appState: AppState

    var body: some View {
        if let error = appState.lastAPIError, appState.nudges.isEmpty {
            errorCard(error)
        } else if appState.nudges.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
                if let error = appState.lastAPIError {
                    errorCard(error)
                }
                ForEach(appState.nudges) { nudge in
                    NudgeCardView(
                        nudge: nudge,
                        followUps: appState.followUps[nudge.id] ?? [],
                        isQuerying: appState.queryingNudgeId == nudge.id,
                        canQuery: appState.canQuery(nudgeId: nudge.id),
                        queryError: appState.queryErrors[nudge.id],
                        screenshot: appState.screenshotCache[nudge.id]
                    ) { question in
                        appState.queryNudge(id: nudge.id, question: question)
                    }
                    .id(nudge.id)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("API Error")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(friendlyError(message))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func friendlyError(_ message: String) -> String {
        if message.contains("credit balance") || message.contains("billing") {
            return "Your Anthropic API account has insufficient credits. Add credits at console.anthropic.com under Plans & Billing."
        }
        if message.contains("invalid x-api-key") || message.contains("authentication") {
            return "Invalid API key. Check your key in Settings."
        }
        if message.contains("No API key") {
            return "No API key configured. Add your Anthropic API key in Settings."
        }
        if message.contains("model") {
            return "Invalid model. Check the model name in Settings."
        }
        return message
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("Monitoring...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Insights will appear here when\nScreenPilot spots something useful.")
                .font(.caption)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
