import XCTest
import UIKit
@testable import Kima

final class ImageCacheSizeTests: XCTestCase {
    private func image(_ side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in }
    }

    func testSizeCountsStoredImagesAndDropsToZeroOnClear() async {
        let cache = ImageCache()
        let a = URL(string: "https://x.test/a.png")!, b = URL(string: "https://x.test/b.png")!
        await cache.store(image(10), for: a)
        await cache.store(image(20), for: b)
        XCTAssertEqual(cache.storedBytes, 10 * 10 * 4 + 20 * 20 * 4)

        await cache.store(image(5), for: a)   // replacing an entry doesn't double-count
        XCTAssertEqual(cache.storedBytes, 5 * 5 * 4 + 20 * 20 * 4)

        await cache.clearAll()
        XCTAssertEqual(cache.storedBytes, 0)
    }
}
