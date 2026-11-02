import Foundation
import UIKit

// Simulator-only stand-ins for types ImageLoader references. They do not fetch,
// parse, or enlarge artwork. The production app build does not compile this file.
public struct Movie: Identifiable, Hashable {
    public var id: String
    public var type: String?
    public var number: String?
    public var thumbURL: String?
    public var coverURL: String?
    public var score: Double?
    public var catalogueMetadata: Meta?
    public struct Meta: Hashable { public var images: [String]; public init(images: [String]) { self.images = images } }
    public init(id: String, type: String? = nil, number: String? = nil, thumbURL: String? = nil, coverURL: String? = nil) {
        self.id = id; self.type = type; self.number = number; self.thumbURL = thumbURL; self.coverURL = coverURL
    }
    public var displayNumber: String { number ?? id }
    public var displayTitle: String { number ?? "Neutral" }
    public var playBadge: String? { nil }
    public var magnetStatusText: String? { nil }
    public var hasCnsub: Bool? { nil }
    public var isNewMagnet: Bool { false }
    public var releaseDate: String? { nil }
    public static func == (lhs: Movie, rhs: Movie) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
enum DMMImageValidation {
    // Same ratios as production DMMCoverResolver. The simulator host never fetches jackets.
    static let standardFrontRatio = 0.703
    static let milkFrontRatio = 0.69
    static func classify(width: Int, height: Int, bytes: Int, source: String) -> String { "ok" }
    static func frontRatio(source: String) -> Double {
        let cid = URL(string: source)?.lastPathComponent.lowercased() ?? ""
        return cid.hasPrefix("h_1240") ? milkFrontRatio : standardFrontRatio
    }
}
final class APIClient { static let shared = APIClient(); var token: String? = "account-a" }
enum JavDBConstants { static let imageCDNHost = "tp.spfcas.com"; static let webCDNHost = "c0.jdbstatic.com"; static let baseURL = "https://fixture.invalid" }
enum JavBusActorRequests { static let version = "fixture" }
enum JavDBSignature { static func decryptImage(_ data: Data) -> Data { data } }
enum CatalogueIdentity { static func parts(_ raw: String) -> (prefix: String, serial: String)? { nil } }
enum DMMCID { static func candidates(number: String) -> [String] { [] } }
enum DMMCoverURLs {
    static func digital(_ cid: String) -> [String] { [] }
    static func upgrade(_ source: String) -> [String] { [] }
    static func isJacket(_ source: String) -> Bool { false }
}
enum DMMPoster { static func allowedImage(_ url: URL) -> Bool { false } }
enum AmazonPoster { static func allowedImage(_ url: URL) -> Bool { url.host == "m.media-amazon.com" } }
enum TenhowPoster { static func allowedImage(_ url: URL) -> Bool { url.host == "www.tenhow.net" } }
enum AvbaseMetadata { static func allowedDiscoveredImage(_ url: URL) -> Bool { url.host == "pic.duga.jp" } }
enum AvbaseHQExtras { static func isDugaJacket(_ url: URL) -> Bool { false }; static func isMGSPrestigePackage(_ url: URL) -> Bool { false } }
struct PosterProvenance: Equatable { let label: String; init(source: String) { label = "fixture" }; var text: String { label } }
enum DetailPosterPolicy {
    static func candidates(number: String?) -> [String] {
        guard let number, number.hasPrefix("NEUTRAL") else { return [] }
        return ["https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/fixture/fixtureps.jpg"]
    }
    static func allowedPublicImage(_ url: URL) -> Bool {
        ["awsimgsrc.dmm.co.jp", "pics.dmm.co.jp", "image.mgstage.com"].contains(url.host ?? "")
    }
}
