import Foundation
import CryptoKit
import UIKit

// Build 298 policy host. Neutral geometry only: no image hosts are contacted.
enum JavDBConstants { static let imageCDNHost = "tp.spfcas.com"; static let webCDNHost = "c0.jdbstatic.com" }
enum JavBusActorRequests { static let version = "fixture" }
final class APIClient { static let shared = APIClient(); var token: String? = "account-a" }

struct Movie {
    var id: String
    var type: String?
    var number: String?
    var thumbURL: String?
    var coverURL: String?
    var catalogueMetadata: Meta?
    struct Meta { var images: [String] }
}

enum FrontPosterPolicy {
    static func usesOriginal(type: String?, number: String?) -> Bool {
        ["1", "2", "3"].contains(type ?? "")
    }
}
enum DMMCoverURLs { static func upgrade(_ source: String) -> [String] { [source + "#hq"] } }
enum DetailPosterPolicy {
    static func candidates(number: String?) -> [String] {
        ["https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/fixture/fixtureps.jpg"]
    }
    static func allowedPublicImage(_ url: URL) -> Bool { url.host == "awsimgsrc.dmm.co.jp" }
}
enum AmazonPoster { static func allowedImage(_ url: URL) -> Bool { false } }
enum TenhowPoster { static func allowedImage(_ url: URL) -> Bool { false } }
enum AvbaseMetadata { static func allowedDiscoveredImage(_ url: URL) -> Bool { false } }

enum VisibleHQPosterPolicy {
    static let concurrency = 2
    static let maxPixelCap = 900
    static let minPixelFloor = 360
    static func targetPixels(displayPoints: CGSize, scale: CGFloat) -> Int {
        let longest = max(displayPoints.width, displayPoints.height) * max(scale, 1)
        return min(maxPixelCap, max(minPixelFloor, Int(longest.rounded(.up))))
    }
    static func isSafeUpgradeHost(_ url: URL) -> Bool {
        url.scheme == "https" && url.query == nil && url.port == nil &&
            (url.host == "awsimgsrc.dmm.co.jp" || url.host == "m.media-amazon.com")
    }
}

let phone = VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 120, height: 171), scale: 3)
assert(phone == 513, "phone card \(phone)")
let pad = VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 220, height: 314), scale: 2)
assert(pad == 628, "pad card \(pad)")
let huge = VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 2000, height: 3000), scale: 3)
assert(huge == 900, "cap \(huge)")
let tiny = VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 10, height: 10), scale: 1)
assert(tiny == 360, "floor \(tiny)")
assert(!VisibleHQPosterPolicy.isSafeUpgradeHost(URL(string: "https://evil.example/a.jpg")!))
assert(!VisibleHQPosterPolicy.isSafeUpgradeHost(URL(string: "http://awsimgsrc.dmm.co.jp/a.jpg")!))
assert(VisibleHQPosterPolicy.isSafeUpgradeHost(URL(string: "https://awsimgsrc.dmm.co.jp/pics_dig/a.jpg")!))
assert(VisibleHQPosterPolicy.concurrency == 2 && VisibleHQPosterPolicy.maxPixelCap == 900)

let account = APIClient.shared.token ?? "guest"
let scope = SHA256.hash(data: Data(("fixture|" + "https://apidd.spthgb.com|" + account).utf8)).map { String(format: "%02x", $0) }.joined()
let other = SHA256.hash(data: Data(("fixture|" + "https://apidd.spthgb.com|account-b").utf8)).map { String(format: "%02x", $0) }.joined()
assert(scope.prefix(16) != other.prefix(16), "account scopes must differ")

// Downsample contract: a 2000px neutral JPEG must come back at the requested cap, never enlarged.
let ctx = CGContext(data: nil, width: 2000, height: 1200, bitsPerComponent: 8, bytesPerRow: 2000 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1200))
let data = NSMutableData()
let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
assert(CGImageDestinationFinalize(dest))
let source = CGImageSourceCreateWithData(data as CFData, nil)!
let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: 513
] as CFDictionary)!
assert(max(thumb.width, thumb.height) <= 513, "downsampled \(thumb.width)x\(thumb.height)")
assert(thumb.width >= 200 && thumb.height >= 120, "not a placeholder")
print("PASS home HQ pixel cap, account scope, downsample \(thumb.width)x\(thumb.height)")
