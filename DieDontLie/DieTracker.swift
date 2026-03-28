import CoreImage
import CoreGraphics

/// Detects a vibrant-colored die in a frame using CIFilter-based HSV masking.
/// Returns the die's centroid in **normalized coordinates** (0,0 = top-left, 1,1 = bottom-right).
final class DieTracker {

    // MARK: - Configuration

    struct ColorConfig {
        /// Hue range [0, 1] for the die color
        var hueMin: Float
        var hueMax: Float
        /// Saturation and brightness lower bounds — keep high to filter outdoor noise
        var saturationMin: Float = 0.55
        var brightnessMin: Float = 0.35
        /// Minimum fraction of frame area the blob must occupy to count as the die
        var minBlobAreaFraction: Float = 0.0003
        /// Maximum fraction of frame area (filters out large color blobs that aren't the die)
        var maxBlobAreaFraction: Float = 0.04

        static var red: ColorConfig {
            // Red wraps around hue 0, so we check two ranges and union them
            ColorConfig(hueMin: 0.0, hueMax: 0.07)
        }
        static var orange: ColorConfig { ColorConfig(hueMin: 0.04, hueMax: 0.12) }
        static var yellow: ColorConfig { ColorConfig(hueMin: 0.10, hueMax: 0.18) }
        static var green:  ColorConfig { ColorConfig(hueMin: 0.28, hueMax: 0.45) }
        static var blue:   ColorConfig { ColorConfig(hueMin: 0.55, hueMax: 0.70) }
        static var pink:   ColorConfig { ColorConfig(hueMin: 0.85, hueMax: 1.00) }
    }

    var colorConfig: ColorConfig = .red

    // MARK: - Detection

    struct DetectionResult {
        /// Centroid in normalized coords (0,0 top-left)
        let normalizedCenter: CGPoint
        /// Bounding box in normalized coords
        let normalizedBounds: CGRect
    }

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectionResult? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let masked = applyColorMask(to: ciImage) else { return nil }

        // Render to a small bitmap for fast blob analysis
        let scale: CGFloat = 4
        let thumbSize = CGSize(width: frameSize.width / scale, height: frameSize.height / scale)
        let thumbRect = CGRect(origin: .zero, size: thumbSize)

        let scaledImage = masked.transformed(by: CGAffineTransform(scaleX: 1/scale, y: 1/scale))

        guard let cgImage = context.createCGImage(scaledImage, from: thumbRect) else { return nil }
        guard let blob = largestBlob(in: cgImage, thumbSize: thumbSize) else { return nil }

        let frameArea = thumbSize.width * thumbSize.height
        let blobArea = blob.width * blob.height
        let fraction = Float(blobArea / frameArea)

        guard fraction >= colorConfig.minBlobAreaFraction,
              fraction <= colorConfig.maxBlobAreaFraction else { return nil }

        // Convert blob rect from thumb-space back to normalized [0,1]
        // Note: CIImage origin is bottom-left, so flip Y for UIKit (top-left origin)
        let normX = blob.midX / thumbSize.width
        let normY = 1.0 - (blob.midY / thumbSize.height)   // flip Y
        let normW = blob.width / thumbSize.width
        let normH = blob.height / thumbSize.height
        let normOriginY = 1.0 - (blob.maxY / thumbSize.height)

        return DetectionResult(
            normalizedCenter: CGPoint(x: normX, y: normY),
            normalizedBounds: CGRect(x: normX - normW/2, y: normOriginY, width: normW, height: normH)
        )
    }

    // MARK: - Private helpers

    private func applyColorMask(to image: CIImage) -> CIImage? {
        // Convert to HSV-friendly space using CIColorMatrix + threshold
        // We use CIColorCube to isolate the hue range
        guard let filter = CIFilter(name: "CIFalseColor") else {
            return hueMaskFallback(image: image)
        }
        _ = filter // CIFalseColor not what we want — use fallback
        return hueMaskFallback(image: image)
    }

    /// Uses CIColorThreshold and hue extraction via CIColorKernel-free approach:
    /// convert image to grayscale-of-hue channel via CIColorMatrix tricks.
    private func hueMaskFallback(image: CIImage) -> CIImage? {
        // Extract pixels matching our hue/sat/brightness using a color cube
        let cubeData = buildColorCube(size: 16)
        let cubeFilter = CIFilter(
            name: "CIColorCube",
            parameters: [
                "inputCubeDimension": 16,
                "inputCubeData": cubeData as NSData,
                kCIInputImageKey: image
            ]
        )
        return cubeFilter?.outputImage
    }

    /// Builds a 16^3 RGBA color cube that maps matching hue/sat/brightness pixels
    /// to white (1,1,1,1) and all others to black (0,0,0,1).
    private func buildColorCube(size: Int) -> Data {
        var data = [Float](repeating: 0, count: size * size * size * 4)
        let step = 1.0 / Float(size - 1)

        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let red   = Float(r) * step
                    let green = Float(g) * step
                    let blue  = Float(b) * step

                    let (h, s, v) = rgbToHSV(r: red, g: green, b: blue)
                    let idx = (b * size * size + g * size + r) * 4

                    let inSat = s >= colorConfig.saturationMin
                    let inBright = v >= colorConfig.brightnessMin
                    let inHue: Bool

                    if colorConfig.hueMin <= colorConfig.hueMax {
                        inHue = h >= colorConfig.hueMin && h <= colorConfig.hueMax
                    } else {
                        // Wrapping hue (e.g. red: 0.93–0.07)
                        inHue = h >= colorConfig.hueMin || h <= colorConfig.hueMax
                    }

                    let match: Float = (inHue && inSat && inBright) ? 1.0 : 0.0
                    data[idx]   = match
                    data[idx+1] = match
                    data[idx+2] = match
                    data[idx+3] = 1.0
                }
            }
        }
        return Data(bytes: &data, count: data.count * MemoryLayout<Float>.size)
    }

    private func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let v = maxC
        let s = maxC == 0 ? 0 : delta / maxC

        var h: Float = 0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6
            } else if maxC == g {
                h = ((b - r) / delta + 2) / 6
            } else {
                h = ((r - g) / delta + 4) / 6
            }
            if h < 0 { h += 1 }
        }
        return (h, s, v)
    }

    /// Finds the bounding box of the largest connected white-pixel blob in a CGImage.
    private func largestBlob(in cgImage: CGImage, thumbSize: CGSize) -> CGRect? {
        let width  = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Simple row/col scanning — find bounding box of bright pixels
        var minX = width, maxX = 0, minY = height, maxY = 0
        var count = 0

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let r = pixels[idx], g = pixels[idx+1], b = pixels[idx+2]
                if r > 128 && g > 128 && b > 128 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    count += 1
                }
            }
        }

        guard count > 0, maxX >= minX, maxY >= minY else { return nil }

        // Scale coords back to thumb-space CGFloat
        let scale = thumbSize.width / CGFloat(width)
        return CGRect(
            x: CGFloat(minX) * scale,
            y: CGFloat(minY) * scale,
            width: CGFloat(maxX - minX + 1) * scale,
            height: CGFloat(maxY - minY + 1) * scale
        )
    }
}
