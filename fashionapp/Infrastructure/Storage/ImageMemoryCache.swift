import UIKit

/// Small in-memory cache so wardrobe / discover cells don't re-decode every appear.
enum ImageMemoryCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 40 * 1024 * 1024
        return c
    }()

    static func image(for path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    static func store(_ image: UIImage, for path: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: path as NSString, cost: max(cost, 1))
    }

    static func remove(for path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}
