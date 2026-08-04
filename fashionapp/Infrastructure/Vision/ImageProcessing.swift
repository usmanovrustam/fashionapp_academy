import UIKit
import CoreVideo
import CoreImage

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

/// Image helpers safe to call from background threads (Core Graphics / encode paths only).
enum ImageProcessing {
    static func uiImage(from data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else { throw ImageProcessingError.invalidImage }
        return image
    }

    static func jpegData(from image: UIImage, quality: CGFloat = 0.9) throws -> Data {
        guard let cgImage = cgImage(from: image) else { throw ImageProcessingError.invalidImage }
        return try jpegData(from: cgImage, quality: quality)
    }

    static func jpegData(from cgImage: CGImage, quality: CGFloat = 0.9) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageProcessingError.invalidImage }
        return data as Data
    }

    static func pngData(from image: UIImage) throws -> Data {
        guard let cgImage = cgImage(from: image) else { throw ImageProcessingError.invalidImage }
        return try pngData(from: cgImage)
    }

    static func pngData(from cgImage: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.invalidImage
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImageProcessingError.invalidImage }
        return data as Data
    }

    /// Thread-safe resize via Core Graphics (no UIGraphicsImageRenderer).
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard let source = cgImage(from: image) else { return image }
        let pixelWidth = CGFloat(source.width)
        let pixelHeight = CGFloat(source.height)
        let maxSide = max(pixelWidth, pixelHeight)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1
        let newW = max(1, Int((pixelWidth * scale).rounded()))
        let newH = max(1, Int((pixelHeight * scale).rounded()))
        guard let resized = redraw(source, width: newW, height: newH) else { return image }
        return UIImage(cgImage: resized, scale: 1, orientation: .up)
    }

    static func pixelBuffer(from image: UIImage, width: Int, height: Int) throws -> CVPixelBuffer {
        guard let source = cgImage(from: image) else { throw ImageProcessingError.invalidImage }
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
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// Applies a grayscale mask as alpha onto the source image (thread-safe CG path).
    static func applyMask(image: UIImage, mask: UIImage) throws -> UIImage {
        guard let source = cgImage(from: image),
              let maskCG = cgImage(from: mask) else {
            throw ImageProcessingError.maskFailed
        }

        let width = source.width
        let height = source.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageProcessingError.maskFailed
        }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Resize mask into gray buffer matching source.
        var maskPixels = [UInt8](repeating: 0, count: width * height)
        guard let maskCtx = CGContext(
            data: &maskPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ImageProcessingError.maskFailed
        }
        // Nearest + hard threshold avoids soft speckles from resized grayscale masks.
        maskCtx.interpolationQuality = .none
        maskCtx.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in 0..<(width * height) {
            let alpha: UInt8 = maskPixels[i] >= 128 ? 255 : 0
            let o = i * 4
            if alpha == 0 {
                pixels[o + 0] = 0
                pixels[o + 1] = 0
                pixels[o + 2] = 0
                pixels[o + 3] = 0
            } else {
                pixels[o + 3] = 255
            }
        }

        guard let out = ctx.makeImage() else { throw ImageProcessingError.maskFailed }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// Crops a centered square around the opaque region of `mask` (thread-safe).
    static func centeredSquareCrop(image: UIImage, mask: UIImage, padding: CGFloat = 0.1) throws -> UIImage {
        guard let source = cgImage(from: image) else { throw ImageProcessingError.invalidImage }
        // Bounds are in source pixel space (mask is redrawn to match image when produced by parser).
        guard var rect = opaquePixelBounds(of: mask, matching: source) else {
            return UIImage(cgImage: centerSquareCG(source), scale: 1, orientation: .up)
        }

        let imageSize = CGSize(width: source.width, height: source.height)
        let pad = max(0, min(0.4, padding))
        rect = rect.insetBy(dx: -rect.width * pad, dy: -rect.height * pad)
        rect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard rect.width > 2, rect.height > 2 else {
            return UIImage(cgImage: centerSquareCG(source), scale: 1, orientation: .up)
        }

        let maxSide = min(imageSize.width, imageSize.height)
        let side = min(max(rect.width, rect.height), maxSide)
        var originX = rect.midX - side / 2
        var originY = rect.midY - side / 2
        originX = max(0, min(originX, imageSize.width - side))
        originY = max(0, min(originY, imageSize.height - side))

        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)
        guard let cropped = redraw(source, crop: cropRect, outputSize: CGSize(width: side, height: side)) else {
            throw ImageProcessingError.invalidImage
        }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    static func centerSquare(_ image: UIImage) -> UIImage {
        guard let source = cgImage(from: image) else { return image }
        return UIImage(cgImage: centerSquareCG(source), scale: 1, orientation: .up)
    }

    /// Bounding box of non-black pixels, mapped into `target` pixel coordinates.
    static func opaquePixelBounds(of mask: UIImage, matching target: CGImage) -> CGRect? {
        guard let maskCG = cgImage(from: mask) else { return nil }
        let width = target.width
        let height = target.height
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
        ctx.interpolationQuality = .high
        ctx.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] >= 128 {
                found = true
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
        guard found else { return nil }
        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }

    /// Bounding box of non-black pixels in a grayscale/alpha mask, in image points.
    static func opaqueBounds(of mask: UIImage) -> CGRect? {
        guard let cg = cgImage(from: mask) else { return nil }
        return opaquePixelBounds(of: mask, matching: cg)
    }

    static func dominantColors(from image: UIImage, maxColors: Int = 5) -> [UIColor] {
        let sample = resized(image, maxDimension: 64)
        guard let cgImage = cgImage(from: sample) else { return [] }

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

    // MARK: - CG helpers (background-safe)

    /// Returns pixel-upright image (orientation baked to `.up`). Required before Core ML / Vision.
    static func orientedUp(_ image: UIImage) -> UIImage {
        guard let cg = cgImage(from: image) else { return image }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Extracts a CGImage with EXIF / `UIImage.imageOrientation` already applied.
    /// Camera JPEGs are often stored landscape with `.right` orientation — using raw
    /// `image.cgImage` without this bake makes SegFormer / crop see a sideways photo.
    static func cgImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage {
            if image.imageOrientation == .up { return cg }
            let oriented = CIImage(cgImage: cg)
                .oriented(cgImageOrientation(from: image.imageOrientation))
            return sharedCIContext.createCGImage(oriented, from: oriented.extent)
        }
        if let ci = image.ciImage {
            let oriented: CIImage
            if image.imageOrientation == .up {
                oriented = ci
            } else {
                oriented = ci.oriented(cgImageOrientation(from: image.imageOrientation))
            }
            return sharedCIContext.createCGImage(oriented, from: oriented.extent)
        }
        return nil
    }

    /// Explicit map — `CGImagePropertyOrientation(_: UIImage.Orientation)` is unavailable
    /// in some SDK / module import combinations and resolves to the `rawValue:` init.
    private static func cgImageOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    static func redraw(_ source: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func redraw(_ source: CGImage, crop: CGRect, outputSize: CGSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let outW = max(1, Int(outputSize.width.rounded()))
        let outH = max(1, Int(outputSize.height.rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        // Draw so the crop rect fills the output.
        let drawRect = CGRect(
            x: -crop.origin.x,
            y: -crop.origin.y,
            width: CGFloat(source.width),
            height: CGFloat(source.height)
        )
        ctx.draw(source, in: drawRect)
        return ctx.makeImage()
    }

    private static func centerSquareCG(_ source: CGImage) -> CGImage {
        let side = min(source.width, source.height)
        let x = (source.width - side) / 2
        let y = (source.height - side) / 2
        let rect = CGRect(x: x, y: y, width: side, height: side)
        if let cropped = source.cropping(to: rect) { return cropped }
        return redraw(source, width: side, height: side) ?? source
    }

    /// RGBA8888 bytes for a CGImage resized to width×height (thread-safe).
    static func rgbaBytes(from image: UIImage, width: Int, height: Int) throws -> [UInt8] {
        guard let source = cgImage(from: image) else { throw ImageProcessingError.invalidImage }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageProcessingError.invalidImage
        }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    static func grayImage(from pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        guard pixels.count >= width * height else { return nil }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
