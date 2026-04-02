import AppKit
import ApplicationServices

protocol InputMonitoring: AnyObject {
    var lastInputTimestamp: Date { get }
    var isScrolling: Bool { get }
    var secondsSinceLastInput: TimeInterval { get }
    func startMonitoring()
    func stopMonitoring()
}

@Observable
@MainActor
final class InputMonitor: InputMonitoring {
    private(set) var lastInputTimestamp: Date = .now
    private(set) var isScrolling: Bool = false

    private var eventMonitors: [Any] = []
    private var scrollResetTask: Task<Void, Never>?

    var secondsSinceLastInput: TimeInterval {
        Date.now.timeIntervalSince(lastInputTimestamp)
    }

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func startMonitoring() {
        let eventTypes: [NSEvent.EventTypeMask] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown
        ]

        for eventType in eventTypes {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: eventType, handler: { [weak self] _ in
                Task { @MainActor in
                    self?.recordActivity()
                }
            }) {
                eventMonitors.append(monitor)
            }
        }

        // Scroll events tracked separately
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] _ in
            Task { @MainActor in
                self?.recordScroll()
            }
        }) {
            eventMonitors.append(monitor)
        }
    }

    func stopMonitoring() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        scrollResetTask?.cancel()
    }

    private func recordActivity() {
        lastInputTimestamp = .now
    }

    private func recordScroll() {
        lastInputTimestamp = .now
        isScrolling = true

        scrollResetTask?.cancel()
        scrollResetTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            isScrolling = false
        }
    }
}
