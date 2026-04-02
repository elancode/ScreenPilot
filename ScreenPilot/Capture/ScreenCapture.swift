import CoreGraphics
import AppKit
import ScreenCaptureKit

struct ScreenCapture {
    /// Maximum width for captured images (reduces API cost).
    private let maxWidth: CGFloat = 1920

    /// Check if Screen Recording permission is granted.
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission (opens System Settings).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Capture the current screen contents as a CGImage using ScreenCaptureKit.
    /// Falls back to CGWindowListCreateImage if SCKit fails.
    /// The returned image is held in memory only — NEVER write to disk.
    func capture() async -> CGImage? {
        if let image = await captureWithScreenCaptureKit() {
            return resizeIfNeeded(image)
        }
        if let image = captureWithCGWindowList() {
            return resizeIfNeeded(image)
        }
        return nil
    }

    private func captureWithScreenCaptureKit() async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            print("[ScreenPilot] ScreenCaptureKit capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func captureWithCGWindowList() -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    private func resizeIfNeeded(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        guard width > maxWidth else { return image }

        let scale = maxWidth / width
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }
}
