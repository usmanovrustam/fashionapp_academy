import UIKit
import CoreVideo

enum ImageProcessingError: LocalizedError {
    case invalidImage
    case pixelBufferFailed
    case maskFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not read image data."
        case .pixelBufferFailed: return "Failed to create pixel buffer."
        case .maskFailed: return "Failed to apply segmentation mask."
        }
    }
}

enum ImageProcessing {
    static func uiImage(from data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else { throw ImageProcessingError.invalidImage }
        return image
    }

    static func jpegData(from image: UIImage, quality: CGFloat = 0.9) throws -> Data {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw ImageProcessingError.invalidImage
        }
        return data
    }

    static func pngData(from image: UIImage) throws -> Data {
        guard let data = image.pngData() else { throw ImageProcessingError.invalidImage }
        return data
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        // Always redraw so camera images without a CGImage get a bitmap (Vision needs cgImage).
        let newSize: CGSize
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            newSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            newSize = size
        }
        guard newSize.width > 0, newSize.height > 0 else { return image }
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func pixelBuffer(from image: UIImage, width: Int, height: Int) throws -> CVPixelBuffer {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw ImageProcessingError.pixelBufferFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw ImageProcessingError.pixelBufferFailed
        }

        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return buffer
    }

    /// Applies a grayscale mask as alpha onto the source image and returns a transparent PNG-capable UIImage.
    static func applyMask(image: UIImage, mask: UIImage) throws -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let result = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            image.draw(in: rect)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
        guard result.cgImage != nil else { throw ImageProcessingError.maskFailed }
        return result
    }

    /// Crops a centered square around the opaque region of `mask`, with optional padding (0–0.4 of side).
    static func centeredSquareCrop(image: UIImage, mask: UIImage, padding: CGFloat = 0.1) throws -> UIImage {
        guard let bounds = opaqueBounds(of: mask) else {
            // Fallback: center square of the full image.
            return centerSquare(image)
        }

        let pad = max(0, min(0.4, padding))
        var rect = bounds.insetBy(dx: -bounds.width * pad, dy: -bounds.height * pad)
        rect = rect.intersection(CGRect(origin: .zero, size: image.size))
        guard rect.width > 2, rect.height > 2 else { return centerSquare(image) }

        let maxSide = min(image.size.width, image.size.height)
        let side = min(max(rect.width, rect.height), maxSide)
        var originX = rect.midX - side / 2
        var originY = rect.midY - side / 2
        originX = max(0, min(originX, image.size.width - side))
        originY = max(0, min(originY, image.size.height - side))
        let square = CGRect(x: originX, y: originY, width: side, height: side)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -square.minX, y: -square.minY))
        }
    }

    static func centerSquare(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }

    /// Bounding box of non-black pixels in a grayscale/alpha mask, in image points.
    static func opaqueBounds(of mask: UIImage) -> CGRect? {
        guard let cgImage = mask.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            for x in 0..<width {
                if pixels[y * width + x] > 24 {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard found else { return nil }

        let scaleX = mask.size.width / CGFloat(width)
        let scaleY = mask.size.height / CGFloat(height)
        return CGRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )
    }

    static func dominantColors(from image: UIImage, maxColors: Int = 5) -> [UIColor] {
        let sample = resized(image, maxDimension: 64)
        guard let cgImage = sample.cgImage else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [String: (count: Int, r: Int, g: Int, b: Int)] = [:]
        let step = max(1, (width * height) / 800)

        for i in stride(from: 0, to: width * height, by: step) {
            let offset = i * bytesPerPixel
            let a = Int(raw[offset + 3])
            if a < 40 { continue }
            let r = Int(raw[offset]) / 32 * 32
            let g = Int(raw[offset + 1]) / 32 * 32
            let b = Int(raw[offset + 2]) / 32 * 32
            let key = "\(r)-\(g)-\(b)"
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.r += Int(raw[offset])
            bucket.g += Int(raw[offset + 1])
            bucket.b += Int(raw[offset + 2])
            buckets[key] = bucket
        }

        return buckets.values
            .sorted { $0.count > $1.count }
            .prefix(maxColors)
            .map { bucket in
                let c = max(bucket.count, 1)
                return UIColor(
                    red: CGFloat(bucket.r / c) / 255,
                    green: CGFloat(bucket.g / c) / 255,
                    blue: CGFloat(bucket.b / c) / 255,
                    alpha: 1
                )
            }
    }

    static func hexString(from color: UIColor) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }

    static func colorName(from color: UIColor) -> String {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if b < 0.15 { return "Black" }
        if b > 0.9 && s < 0.12 { return "White" }
        if s < 0.12 { return "Gray" }

        switch h {
        case 0..<0.06, 0.95...1: return "Red"
        case 0.06..<0.13: return "Orange"
        case 0.13..<0.2: return "Yellow"
        case 0.2..<0.45: return "Green"
        case 0.45..<0.55: return "Teal"
        case 0.55..<0.7: return "Blue"
        case 0.7..<0.8: return "Purple"
        case 0.8..<0.95: return "Pink"
        default: return "Neutral"
        }
    }
}
