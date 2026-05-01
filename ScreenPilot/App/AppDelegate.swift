import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let appState = AppState()
    private var captureScheduler: CaptureScheduler?
    private var inputMonitor: InputMonitor?
    private var windowTracker: WindowTracker?
    private let llmClient = LLMClient()
    private var contextWindow = ContextWindow()
    private var analysisRouter: AnalysisRouter?
    private var memoryManager: MemoryManager?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(appState: appState)
        NudgeOverlayPanel.shared.onTapped = { [weak self] in
            self?.statusBarController?.showPopover()
        }

        let monitor = InputMonitor()
        let tracker = WindowTracker()
        inputMonitor = monitor
        windowTracker = tracker

        let scheduler = CaptureScheduler(
            inputMonitor: monitor,
            windowTracker: tracker,
            appState: appState
        )

        let memory = MemoryManager()
        memoryManager = memory

        analysisRouter = AnalysisRouter(
            llmClient: llmClient,
            contextWindow: contextWindow,
            appState: appState,
            memoryManager: memory
        )

        scheduler.analysisHandler = { [weak self] image, appName, windowTitle in
            guard let router = self?.analysisRouter else { return nil }
            let result = await router.analyze(image: image, appName: appName, windowTitle: windowTitle)
            // Cache screenshot with nudge for follow-up queries
            if let nudge = result?.nudge {
                await MainActor.run { self?.appState.screenshotCache[nudge.id] = image }
            }
            return result
        }

        // Wire up follow-up query handler
        appState.queryHandler = { [weak self] image, nudge, history, question in
            guard let router = self?.analysisRouter else {
                throw LLMError.missingAPIKey
            }
            return try await router.followUp(
                image: image,
                nudge: nudge,
                previousFollowUps: history,
                question: question
            )
        }

        captureScheduler = scheduler

        // Start input/window monitoring
        monitor.startMonitoring()
        tracker.startTracking()

        // Start the capture scheduler — runLoop gates on appState.isRunning
        scheduler.start()

        // Open database
        Task { [appState, memory] in
            do {
                try await Database.shared.open()
                try await Database.shared.deleteOldRecords()
                await appState.loadSettings()
                await memory.initialize()
            } catch {
                print("[ScreenPilot] Database error: \(error.localizedDescription)")
            }
        }

        // Observe sleep/wake
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.captureScheduler?.stop()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.appState.isRunning else { return }
                self.captureScheduler?.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { [memoryManager] in
            await memoryManager?.shutdown()
            await Database.shared.close()
        }
    }
}
