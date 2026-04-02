import SwiftUI

struct NudgeFeedView: View {
    @Bindable var appState: AppState

    var body: some View {
        if appState.nudges.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
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
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
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
