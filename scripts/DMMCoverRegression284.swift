// Build 284: IPX-706 class (800×538 pl-only DMM titles) must show the DMM cover, not JavDB.
import Foundation
func check(_ c: @autoclosure () -> Bool, _ m: String, line: Int = #line) { if !c() { print("FAIL line \(line): \(m)"); exit(1) } }

let aws = "https://awsimgsrc.dmm.co.jp/pics_dig", pics = "https://pics.dmm.co.jp"
// candidates for a no-prefix label
check(DMMCID.candidates(number: "IPX-706").first == "ipx00706", "IPX digital cid")
let ipx = DetailPosterPolicy.candidates(number: "IPX-706")
check(ipx == ["\(aws)/digital/video/ipx00706/ipx00706ps.jpg", "\(aws)/digital/video/ipx00706/ipx00706pl.jpg"], "IPX-706 candidates \(ipx)")
check(ipx.allSatisfy { DetailPosterPolicy.allowedPublicImage(URL(string: $0)!) }, "admitted")
// mono cid + same-image alternates (host and storefront), never another title
check(DMMCoverURLs.monoCID("ipx00706") == "ipx706" && DMMCoverURLs.monoCID("h_1240milk00311") == "h_1240milk311" && DMMCoverURLs.monoCID("1stars00123") == "1stars123", "mono cid")
check(DMMCoverURLs.monoCID("ssis00001") == "ssis001", "3-digit floor")
check(DMMCoverURLs.fallbacks(for: ipx[1]) == ["\(pics)/digital/video/ipx00706/ipx00706pl.jpg", "\(aws)/mono/movie/ipx706/ipx706pl.jpg", "\(pics)/mono/movie/adult/ipx706/ipx706pl.jpg"], "pl alternates \(DMMCoverURLs.fallbacks(for: ipx[1]))")
check(DMMCoverURLs.fallbacks(for: ipx[0]) == ["\(aws)/mono/movie/ipx706/ipx706ps.jpg"], "ps alternates")
check(DMMCoverURLs.fallbacks(for: "\(aws)/mono/movie/ipx706/ipx706pl.jpg") == ["\(pics)/mono/movie/adult/ipx706/ipx706pl.jpg"], "mono pl alternate")
check(DMMCoverURLs.fallbacks(for: "https://c0.jdbstatic.com/covers/pr/pRX45.jpg").isEmpty, "JavDB has no alternates")
check(DMMCoverURLs.fallbacks(for: ipx[1]).allSatisfy { DMMCoverURLs.cid($0)?.hasSuffix("706") == true }, "same title")
// placeholders: IPX-706 ps is the 147×200 NOW-size thumb; pl 800×538 is a real jacket
check(DMMImageValidation.classify(width: 147, height: 200, bytes: 16939, source: ipx[0]) == .placeholder, "147×200 ps rejected")
check(DMMImageValidation.classify(width: 800, height: 538, bytes: 190075, source: ipx[1]) == .jacket, "800×538 pl is a jacket")
let crop = DMMImageValidation.frontCrop(width: 800, height: 538, source: ipx[1])!
// Build 285: measured 0.703·h front (was 0.69 → 371 px, trimming the left edge).
check(crop.width == 378 && crop.x == 422, "front crop \(crop)")
// the race/tie that showed 封面来源：JavDB: DMM crop 371×538 vs JavDB 800×538 crop 376×538
let dmm = DetailPosterQuality(source: ipx[1], width: 371, height: 538, originalPortrait: false)
let javdb = DetailPosterQuality(source: "https://c0.jdbstatic.com/covers/pr/pRX45.jpg", width: 376, height: 538, originalPortrait: false)
check(javdb.score > dmm.score, "fixture reproduces the 282/283 tie (JavDB scored higher)")
check(DetailPosterQuality.winner([javdb, dmm])!.source == ipx[1], "official DMM wins the near-tie")
check(DetailPosterQuality.winner([dmm, javdb])!.source == ipx[1], "order independent")
check(PosterProvenance(source: DetailPosterQuality.winner([javdb, dmm])!.source).text == "封面来源：DMM", "封面来源：DMM")
// alternates keep provenance
for alt in DMMCoverURLs.fallbacks(for: ipx[1]) { check(PosterProvenance(source: alt).label == "DMM", alt) }
// guards: a much larger JavDB raster still wins; an original portrait still beats crops
let bigJavDB = DetailPosterQuality(source: "https://c0.jdbstatic.com/covers/x/y.jpg", width: 752, height: 1076, originalPortrait: false)
check(DetailPosterQuality.winner([bigJavDB, dmm])!.source == bigJavDB.source, "no blind source bonus beyond 5%")
let milkPS = DetailPosterQuality(source: "\(aws)/digital/video/h_1240milk00311/h_1240milk00311ps.jpg", width: 745, height: 1081, originalPortrait: true)
let milkJ = DetailPosterQuality(source: "https://c0.jdbstatic.com/covers/a/b.jpg", width: 378, height: 541, originalPortrait: false)
check(DetailPosterQuality.winner([milkJ, milkPS])!.source == milkPS.source, "MILK-311 unchanged")
let amazon = DetailPosterQuality(source: "https://m.media-amazon.com/images/I/x.jpg", width: 375, height: 538, originalPortrait: false)
check(DetailPosterQuality.winner([amazon, dmm, javdb])!.officialRank == 0, "official family first")

// cache: JavDB fallback winners expire fast; DMM winners keep the normal TTL
final class Box: @unchecked Sendable { var calls = 0 }
let box = Box()
let cache = DetailPosterCache<String>(positiveTTL: 120, negativeTTL: 30, ttl: { $0 == "JavDB" ? 0.2 : nil })
let sem = DispatchSemaphore(value: 0)
Task {
    box.calls = 0
    _ = await cache.value(key: "IPX-706") { box.calls += 1; return "JavDB" }
    _ = await cache.value(key: "IPX-706") { box.calls += 1; return "JavDB" }
    check(box.calls == 1, "fresh hit served from cache")
    try? await Task.sleep(nanoseconds: 350_000_000)
    let upgraded = await cache.value(key: "IPX-706") { box.calls += 1; return "DMM" }
    check(upgraded == "DMM" && box.calls == 2, "stale JavDB fallback re-resolved to DMM")
    try? await Task.sleep(nanoseconds: 350_000_000)
    _ = await cache.value(key: "IPX-706") { box.calls += 1; return "DMM" }
    check(box.calls == 2, "DMM winner keeps normal TTL")
    sem.signal()
}
sem.wait()
print("PASS dmm284: IPX-706 candidates + same-image host/storefront alternates, 147×200 ps rejected, 800×538 pl cropped, official DMM wins the near-tie vs JavDB, bigger JavDB still wins beyond 5%, stale JavDB fallback re-resolves")
