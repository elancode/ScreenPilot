import CoreGraphics

struct ImageDiff {
    private let hashSize = 32

    /// Compare two CGImages and return a similarity score 0.0–1.0.
    /// 0.0 = completely different, 1.0 = identical.
    func similarity(_ a: CGImage, _ b: CGImage) -> Double {
        let (hashA, meanA) = perceptualHash(a)
        let (hashB, meanB) = perceptualHash(b)

        guard hashA.count == hashB.count, !hashA.isEmpty else { return 0.0 }

        // Structural similarity from hash
        let totalBits = hashA.count * 8
        var matchingBits = 0

        for i in 0..<hashA.count {
            let xor = hashA[i] ^ hashB[i]
            matchingBits += 8 - xor.nonzeroBitCount
        }

        let hashSimilarity = Double(matchingBits) / Double(totalBits)

        // Mean intensity similarity (catches solid color changes)
        let meanDiff = abs(Double(meanA) - Double(meanB)) / 255.0
        let meanSimilarity = 1.0 - meanDiff

        // Combine: weighted average (structure matters more, but mean catches edge cases)
        return hashSimilarity * 0.7 + meanSimilarity * 0.3
    }

    /// Returns true if images are "different enough" to warrant a new capture.
    func isDifferentEnough(_ a: CGImage, _ b: CGImage, threshold: Double = 0.85) -> Bool {
        similarity(a, b) < threshold
    }

    // MARK: - Perceptual Hash

    private func perceptualHash(_ image: CGImage) -> (hash: [UInt8], mean: UInt8) {
        let size = hashSize
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return ([], 0)
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return ([], 0) }

        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)
        let pixelCount = size * size

        // Compute average
        var sum: Int = 0
        for i in 0..<pixelCount {
            sum += Int(pixels[i])
        }
        let average = UInt8(sum / pixelCount)

        // Generate hash: 1 bit per pixel (above/below average)
        let hashBytes = (pixelCount + 7) / 8
        var hash = [UInt8](repeating: 0, count: hashBytes)

        for i in 0..<pixelCount {
            if pixels[i] > average {
                hash[i / 8] |= (1 << (7 - (i % 8)))
            }
        }

        return (hash, average)
    }
}
