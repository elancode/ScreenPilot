import SwiftUI

struct MainDropdownView: View {
    @Bindable var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            copilotView
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            Text("ScreenPilot")
                .font(.headline)
                .fontWeight(.bold)

            statusBadge

            Spacer()

            Button {
                appState.isRunning.toggle()
            } label: {
                Image(systemName: appState.isRunning ? "pause" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help("Settings")
            .popover(isPresented: $showingSettings) {
                SettingsView(appState: appState)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(appState.isRunning ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(appState.isRunning ? "RUNNING" : "PAUSED")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(appState.isRunning ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
        )
        .foregroundStyle(appState.isRunning ? .green : .gray)
    }

    // MARK: - Tab Content

    private var copilotView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    NudgeFeedView(appState: appState)
                }
            }
            .frame(maxHeight: 380)
            .onAppear { scrollToTop(proxy) }
            .onChange(of: appState.nudges.first?.id) { _, _ in scrollToTop(proxy) }
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = appState.nudges.first else { return }
        DispatchQueue.main.async {
            withAnimation(.none) {
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

}
