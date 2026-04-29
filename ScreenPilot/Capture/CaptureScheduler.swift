import Foundation
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.screenpilot", category: "CaptureScheduler")

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
    private var lastResetDay: Int = Calendar.current.component(.day, from: .now)

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
        logger.info("CaptureScheduler started")
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
            let idleSeconds = inputMonitor.secondsSinceLastInput
            if idleSeconds > idleTimeout {
                logger.debug("Skipping: user idle for \(idleSeconds, format: .fixed(precision: 0))s")
                state = .idle
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            state = .active

            // Check blocklist
            if isBlocklisted(windowTracker.currentBundleId) {
                let bundleId = self.windowTracker.currentBundleId
                logger.debug("Skipping: blocklisted app \(bundleId)")
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // Reset daily counter at midnight
            let today = Calendar.current.component(.day, from: .now)
            if today != lastResetDay {
                lastResetDay = today
                appState.resetDailyCounter()
                logger.info("Daily counter reset")
            }

            // Check budget
            if appState.isBudgetExhausted {
                let calls = self.appState.apiCallsToday
                let limit = self.appState.dailyBudgetLimit
                logger.debug("Skipping: budget exhausted (\(calls)/\(limit))")
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            // Check backoff (diminishing returns)
            if consecutiveNothingCount >= backoffThreshold && lastAppContext == windowTracker.currentBundleId {
                let count = self.consecutiveNothingCount
                logger.debug("Skipping: backoff (consecutive nothing: \(count))")
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
                logger.error("Screenshot capture returned nil — check Screen Recording permission")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Check diff (skip if screen unchanged, unless app changed)
            let appChanged = windowTracker.didAppChange
            if !appChanged, let lastImage = lastSentImage, !imageDiff.isDifferentEnough(image, lastImage, threshold: diffThreshold) {
                logger.debug("Skipping: screen unchanged")
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
            let appName = self.windowTracker.currentApp
            let callNum = self.appState.apiCallsToday + 1
            logger.info("Sending screenshot to API (app: \(appName), call #\(callNum))")

            if let handler = analysisHandler {
                let result = await handler(image, windowTracker.currentApp, windowTracker.currentWindowTitle)

                if let result {
                    if let error = result.error {
                        appState.lastAPIError = error
                    } else {
                        appState.lastAPIError = nil
                        appState.apiCallsToday += 1
                        appState.currentActivity = result.activitySummary
                        if let nudge = result.nudge {
                            print("[ScreenPilot] Nudge generated: \(nudge.title)")
                            appState.addNudge(nudge)
                            consecutiveNothingCount = 0
                        } else {
                            consecutiveNothingCount += 1
                            print("[ScreenPilot] No nudge (consecutive nothing: \(consecutiveNothingCount))")
                        }
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
