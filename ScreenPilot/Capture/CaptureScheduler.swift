import Foundation
import CoreGraphics

@Observable
@MainActor
final class CaptureScheduler {
    enum State: Equatable {
        case idle
        case active
        case capturing
    }

    private(set) var state: State = .idle

    private let screenCapture: ScreenCapture
    private let imageDiff: ImageDiff
    private let inputMonitor: InputMonitoring
    private let windowTracker: WindowTracker
    private let appState: AppState

    private var lastSentImage: CGImage?
    private var lastSentTimestamp: Date?
    private var consecutiveNothingCount: Int = 0
    private var lastAppContext: String?
    private var schedulerTask: Task<Void, Never>?

    // Configuration
    private let idleTimeout: TimeInterval = 120      // 2 minutes
    private let minAPIInterval: TimeInterval = 5     // seconds between API calls
    private let diffThreshold: Double = 0.85
    private let backoffInterval: TimeInterval = 60   // seconds during backoff
    private let backoffThreshold: Int = 3            // consecutive "nothing" before backoff

    /// Default blocklist — password managers, keychain, sensitive apps
    private let defaultBlocklist: Set<String> = [
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
    ]

    var analysisHandler: ((CGImage, String, String) async -> AnalysisResult?)?

    init(
        screenCapture: ScreenCapture = ScreenCapture(),
        imageDiff: ImageDiff = ImageDiff(),
        inputMonitor: InputMonitoring,
        windowTracker: WindowTracker,
        appState: AppState
    ) {
        self.screenCapture = screenCapture
        self.imageDiff = imageDiff
        self.inputMonitor = inputMonitor
        self.windowTracker = windowTracker
        self.appState = appState
    }

    func start() {
        guard schedulerTask == nil else { return }
        print("[ScreenPilot] CaptureScheduler started")
        state = .active
        schedulerTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        state = .idle
        lastSentImage = nil
    }

    // MARK: - Main Loop

    private func runLoop() async {
        while !Task.isCancelled {
            guard appState.isRunning else {
                state = .idle
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // Check idle
            if inputMonitor.secondsSinceLastInput > idleTimeout {
                state = .idle
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            state = .active

            // Check blocklist
            if isBlocklisted(windowTracker.currentBundleId) {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // Check budget
            if appState.isBudgetExhausted {
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            // Check backoff (diminishing returns)
            if consecutiveNothingCount >= backoffThreshold && lastAppContext == windowTracker.currentBundleId {
                try? await Task.sleep(for: .seconds(backoffInterval))
                consecutiveNothingCount = 0 // Reset after waiting
                continue
            }

            // Rate limit
            if let lastSent = lastSentTimestamp, Date.now.timeIntervalSince(lastSent) < minAPIInterval {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // Capture
            guard let image = await screenCapture.capture() else {
                print("[ScreenPilot] Screenshot capture returned nil — check Screen Recording permission")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Check diff (skip if screen unchanged, unless app changed)
            let appChanged = windowTracker.didAppChange
            if !appChanged, let lastImage = lastSentImage, !imageDiff.isDifferentEnough(image, lastImage, threshold: diffThreshold) {
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            if appChanged {
                windowTracker.acknowledgeAppChange()
                // Reset backoff on app change
                consecutiveNothingCount = 0
                lastAppContext = windowTracker.currentBundleId
            }

            // Send to analysis
            state = .capturing
            lastSentImage = image
            lastSentTimestamp = .now
            print("[ScreenPilot] Sending screenshot to API (app: \(windowTracker.currentApp), call #\(appState.apiCallsToday + 1))")

            if let handler = analysisHandler {
                let result = await handler(image, windowTracker.currentApp, windowTracker.currentWindowTitle)
                appState.apiCallsToday += 1

                if let result {
                    appState.currentActivity = result.activitySummary
                    if let nudge = result.nudge {
                        print("[ScreenPilot] Nudge generated: \(nudge.title)")
                        appState.addNudge(nudge)
                        consecutiveNothingCount = 0
                    } else {
                        consecutiveNothingCount += 1
                        print("[ScreenPilot] No nudge (consecutive nothing: \(consecutiveNothingCount))")
                    }
                } else {
                    print("[ScreenPilot] Analysis returned nil (API error?)")
                }
            }

            state = .active
            // Scroll handling: slower interval during scrolling
            let sleepInterval: TimeInterval = inputMonitor.isScrolling ? 5 : 2
            try? await Task.sleep(for: .seconds(sleepInterval))
        }
    }

    // MARK: - Blocklist

    private func isBlocklisted(_ bundleId: String) -> Bool {
        if defaultBlocklist.contains(bundleId) { return true }
        if appState.customBlocklist.contains(bundleId) { return true }
        let lowerName = windowTracker.currentApp.lowercased()
        return lowerName.contains("password") || lowerName.contains("vault")
    }
}
