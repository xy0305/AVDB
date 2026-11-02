import Foundation
import UIKit

// Simulator-only stand-ins for types ImageLoader references. They do not fetch,
// parse, or enlarge artwork. The production app build does not compile this file.
struct Movie: Identifiable, Hashable {
    var id: String
    var type: String?
    var number: String?
    var thumbURL: String?
    var coverURL: String?
    var score: Double?
    var catalogueMetadata: Meta?
    struct Meta { var images: [String] }
    var displayNumber: String { number ?? id }
    var displayTitle: String { number ?? "Neutral" }
    var playBadge: String? { nil }
    var magnetStatusText: String? { nil }
    var hasCnsub: Bool? { nil }
    var isNewMagnet: Bool { false }
    var releaseDate: String? { nil }
}
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
