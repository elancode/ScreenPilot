import XCTest
@testable import ScreenPilot

final class ImageDiffTests: XCTestCase {
    private var sut: ImageDiff!

    override func setUp() {
        super.setUp()
        sut = ImageDiff()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_identicalImages_returnsHighSimilarity() {
        let image = createTestImage(color: .white)
        let similarity = sut.similarity(image, image)
        XCTAssertGreaterThan(similarity, 0.99, "Identical images should have >99% similarity")
    }

    func test_completelyDifferentImages_returnsLowerSimilarity() {
        let white = createTestImage(color: .white)
        let black = createTestImage(color: .black)
        let similarity = sut.similarity(white, black)
        // Perceptual hash of uniform colors: hash bits are identical (all 0),
        // but mean intensity differs. Expect noticeably below 1.0.
        XCTAssertLessThan(similarity, 0.85, "Black vs white should be below diff threshold")
    }

    func test_isDifferentEnough_identicalImages_returnsFalse() {
        let image = createTestImage(color: .white)
        XCTAssertFalse(sut.isDifferentEnough(image, image))
    }

    func test_isDifferentEnough_differentImages_returnsTrue() {
        let white = createTestImage(color: .white)
        let black = createTestImage(color: .black)
        XCTAssertTrue(sut.isDifferentEnough(white, black))
    }

    func test_isDifferentEnough_respectsThreshold() {
        let white = createTestImage(color: .white)
        let black = createTestImage(color: .black)
        // With threshold 0.0, everything is "similar enough" (similarity >= 0.0)
        XCTAssertFalse(sut.isDifferentEnough(white, black, threshold: 0.0))
        // Black vs white should be different enough at default threshold (0.85)
        XCTAssertTrue(sut.isDifferentEnough(white, black, threshold: 0.85))
    }

    // MARK: - Helpers

    private func createTestImage(color: NSColor) -> CGImage {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        return context.makeImage()!
    }
}
