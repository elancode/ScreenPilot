import AppKit
import ApplicationServices

@Observable
@MainActor
final class WindowTracker {
    private(set) var currentApp: String = ""
    private(set) var currentBundleId: String = ""
    private(set) var currentWindowTitle: String = ""
    private(set) var didAppChange: Bool = false

    private var workspaceObserver: NSObjectProtocol?
    private var pollingTask: Task<Void, Never>?

    func startTracking() {
        updateCurrentApp()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppActivation(notification)
            }
        }

        // Poll window title every second (can change without app change, e.g. switching tabs)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self?.updateWindowTitle()
            }
        }
    }

    func stopTracking() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObserver = nil
        pollingTask?.cancel()
    }

    func acknowledgeAppChange() {
        didAppChange = false
    }

    // MARK: - Private

    private func handleAppActivation(_ notification: Notification) {
        let previousBundleId = currentBundleId
        updateCurrentApp()
        if currentBundleId != previousBundleId {
            didAppChange = true
        }
    }

    private func updateCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        currentApp = app.localizedName ?? ""
        currentBundleId = app.bundleIdentifier ?? ""
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else { return }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)

        if titleResult == .success, let title = titleValue as? String {
            currentWindowTitle = title
        }
    }
}
