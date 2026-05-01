import AppKit
import SwiftUI
import os.log

private let overlayLogger = Logger(subsystem: "com.screenpilot", category: "Overlay")

@MainActor
final class NudgeOverlayPanel {
    static let shared = NudgeOverlayPanel()

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var pinned = false
    var onTapped: (() -> Void)?

    private init() {}

    func show(nudge: Nudge) {
        dismissTask?.cancel()
        dismissTask = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        pinned = false

        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = 360
        let maxHeight = screen.visibleFrame.height - 32

        // Measure content height using a sized hosting view
        let measureHost = NSHostingView(rootView:
            NudgeOverlayView(title: nudge.title, message: nudge.body, onDismiss: {})
        )
        measureHost.setFrameSize(NSSize(width: panelWidth, height: 0))
        measureHost.layoutSubtreeIfNeeded()
        let measured = measureHost.fittingSize.height
        let panelHeight = min(max(measured, 80), maxHeight)

        let margin: CGFloat = 16
        let x = screen.visibleFrame.maxX - panelWidth - margin
        let y = screen.visibleFrame.maxY - panelHeight - margin

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let view = NudgeOverlayView(
            title: nudge.title,
            message: nudge.body,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: panelWidth))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        panel.orderFrontRegardless()
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        self.window = panel

        overlayLogger.warning("Panel: x=\(x, privacy: .public) y=\(y, privacy: .public) w=\(panelWidth, privacy: .public) h=\(panelHeight, privacy: .public)")

        // Cancel auto-dismiss when user clicks inside the panel
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if event.window === self?.window {
                self?.pinned = true
                self?.dismissTask?.cancel()
                self?.dismissTask = nil
            }
            return event
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !self.pinned else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

private struct NudgeOverlayView: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("ScreenPilot")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text(markdownString(title))
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(markdownString(message))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
    }
}
