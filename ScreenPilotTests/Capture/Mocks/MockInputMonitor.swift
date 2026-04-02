import Foundation
@testable import ScreenPilot

@MainActor
final class MockInputMonitor: InputMonitoring {
    var lastInputTimestamp: Date = .now
    var isScrolling: Bool = false
    var startMonitoringCalled = false
    var stopMonitoringCalled = false

    var secondsSinceLastInput: TimeInterval {
        Date.now.timeIntervalSince(lastInputTimestamp)
    }

    func startMonitoring() {
        startMonitoringCalled = true
    }

    func stopMonitoring() {
        stopMonitoringCalled = true
    }

    func simulateActivity() {
        lastInputTimestamp = .now
    }

    func simulateIdle(seconds: TimeInterval) {
        lastInputTimestamp = Date.now.addingTimeInterval(-seconds)
    }
}
