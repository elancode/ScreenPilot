import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private var eventMonitor: Any?
    private var observationTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        setup()
        updateIcon()
        startObserving()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "ScreenPilot")?.withSymbolConfiguration(config)
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MainDropdownView(appState: appState)
        )
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func startObserving() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.appState.unreadCount
                        _ = self.appState.isRunning
                    } onChange: {
                        continuation.resume()
                    }
                }
                self.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName = appState.isRunning ? "paperplane.fill" : "paperplane"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ScreenPilot")?.withSymbolConfiguration(config)
        button.image?.isTemplate = true

        if appState.unreadCount > 0 {
            button.title = " \(appState.unreadCount)"
        } else {
            button.title = ""
        }
    }
}
