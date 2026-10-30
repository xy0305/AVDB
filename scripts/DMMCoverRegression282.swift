// Build 282 DMM HQ cover regression (swiftc with JavRankingCore, TenhowPoster, DetailPosterPolicy,
// DMMCoverResolver, DMMLabelSeed). Offline and deterministic.
import Foundation

func check(_ c: @autoclosure () -> Bool, _ m: String, line: Int = #line) { if !c() { print("FAIL line \(line): \(m)"); exit(1) } }

// ---- CID parsing / candidates
check(DMMCID.parts("MILK-311")! == ("milk", 311), "parts")
check(DMMCID.parts("FC2-123456") == nil, "FC2 excluded")
check(DMMCID.pad(311, 5) == "00311" && DMMCID.pad(7, 3) == "007", "pad")
check(DMMCID.candidates(number: "MILK-311").first == "h_1240milk00311", "MILK → h_1240 + 5-digit pad: \(DMMCID.candidates(number: "MILK-311"))")
check(DMMCID.candidates(number: "SSIS-001").first == "ssis00001", "plain label")
check(DMMCID.candidates(number: "STARS-123").first == "1stars00123", "pre-282 rule kept")
check(DMMCID.candidates(number: "ABP-123").first == "118abp00123", "118 prefix")
check(DMMCID.candidates(number: "REBD-900").first == "h_346rebd00900", "h_346 prefix")
check(DMMCID.candidates(number: "ZZQQ-12") == ["zzqq00012", "zzqq012"], "unknown label → 5 then 3 digit pad")
check(DMMLabelSeed.table.count >= 60, "seed table populated (\(DMMLabelSeed.table.count))")

// ---- learning + persistence + exact mapping
let suite = "dmm282." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
let table = DMMLabelPrefixes(defaults: defaults)
check(DMMCID.learn(cid: "h_1240milk00311", number: "MILK-311")! == ("h_1240", 5), "learn prefix")
check(DMMCID.learn(cid: "h_1240milk00312", number: "MILK-311") == nil, "serial must match")
check(DMMCID.learn(cid: "h_1240abc00311", number: "MILK-311") == nil, "label must match")
check(table.learn(cid: "h_9999newlbl00042", number: "NEWLBL-42"), "learn new label")
check(DMMCID.candidates(number: "NEWLBL-77", table: table).first == "h_9999newlbl00077", "learned rule applies to other serials")
check(table.learn(cid: "odd123", number: "ODD-123") && table.cid(for: "ODD-123") == "odd123", "exact mapping for odd padding")
check(DMMCID.candidates(number: "ODD-123", table: table).first == "odd123", "exact mapping first")
let reopened = DMMLabelPrefixes(defaults: defaults)
check(reopened.rule(for: "newlbl") == .init(prefix: "h_9999", width: 5) && reopened.cid(for: "ODD-123") == "odd123", "persisted")
check(table.allows(label: "milk", prefix: "h_1240") && !table.allows(label: "milk", prefix: "h_999") && table.allows(label: "x", prefix: ""), "prefix admission")
for i in 0..<(DMMLabelPrefixes.cidCap + 10) { table.learn(cid: "cap\(DMMCID.pad(i + 1, 5))", number: "CAP-\(i + 1)") }
check(table.cid(for: "CAP-1") == nil && table.cid(for: "CAP-\(DMMLabelPrefixes.cidCap + 10)") != nil, "exact mapping capped (oldest evicted)")
table.reset(); check(table.cid(for: "ODD-123") == nil, "reset")
defaults.removePersistentDomain(forName: suite)

// ---- URL patterns / admission (production DetailPosterPolicy + DMMPoster)
let milk = DetailPosterPolicy.candidates(number: "MILK-311")
check(milk == ["https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311ps.jpg",
               "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311pl.jpg"], "MILK-311 HQ pair: \(milk)")
check(milk.allSatisfy { DetailPosterPolicy.allowedPublicImage(URL(string: $0)!) }, "MILK-311 HQ admitted")
check(!DetailPosterPolicy.allowedPublicImage(URL(string: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_999milk00311/h_999milk00311ps.jpg")!), "unknown namespace rejected")
check(DMMPoster.candidates(metadata: "https://pics.dmm.co.jp/digital/video/h_1240milk00311/h_1240milk00311ps.jpg", number: "MILK-311").first
      == milk[0], "metadata ps → awsimgsrc HQ")
check(DMMPoster.candidates(metadata: "https://pics.dmm.co.jp/digital/video/h_1240milk00311/h_1240milk00311ps.jpg", number: "MILK-312").isEmpty, "number-bound")
check(DetailPosterPolicy.candidates(number: "ABF-100").allSatisfy { $0.contains("image.mgstage.com") }, "MGS labels unchanged")
check(DMMCoverURLs.upgrade("https://pics.dmm.co.jp/digital/video/h_1240milk00311/h_1240milk00311pl.jpg") == milk, "pics pl upgrade")
check(DMMCoverURLs.upgrade("https://pics.dmm.co.jp/mono/movie/adult/h_1240milk311/h_1240milk311pl.jpg")
      == ["https://awsimgsrc.dmm.co.jp/pics_dig/mono/movie/h_1240milk311/h_1240milk311ps.jpg",
          "https://awsimgsrc.dmm.co.jp/pics_dig/mono/movie/h_1240milk311/h_1240milk311pl.jpg"], "mono upgrade")
check(DMMCoverURLs.upgrade("https://c0.jdbstatic.com/covers/zn/ZN0deq.jpg").isEmpty, "non-DMM untouched")
check(DMMCoverURLs.cid("https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311pl.jpg") == "h_1240milk00311", "cid from path")
check(DMMCoverURLs.amateur("hmdnc953").hasSuffix("/digital/amateur/hmdnc953/hmdnc953jp.jpg"), "amateur pattern")
check(DMMCoverURLs.isJacket(milk[1]) && !DMMCoverURLs.isJacket(milk[0]), "jacket detection")

// ---- validation / placeholders
check(DMMImageValidation.classify(width: 745, height: 1081, bytes: 214079, source: milk[0]) == .portrait, "real ps")
check(DMMImageValidation.classify(width: 1600, height: 1081, bytes: 527118, source: milk[1]) == .jacket, "real pl")
check(DMMImageValidation.classify(width: 147, height: 200, bytes: 13413, source: "x/abcps.jpg") == .placeholder, "147×200 NOW ps")
check(DMMImageValidation.classify(width: 590, height: 800, bytes: 40000, source: "x/abcpl.jpg") == .placeholder, "590×800 NOW pl")
check(DMMImageValidation.classify(width: 800, height: 800, bytes: 2732, source: "x/abcps.jpg") == .placeholder, "2,732-byte body")
check(DMMImageValidation.classify(width: 800, height: 600, bytes: 9000, source: "x/abcps.jpg", finalURL: URL(string: "https://pics.dmm.com/mono/noimage/now_printing.jpg")) == .placeholder, "now_printing redirect")
check(DMMImageValidation.classify(width: 300, height: 400, bytes: 20000, source: "x/abcps.jpg") == .tooSmall, "small ps")
let crop = DMMImageValidation.frontCrop(width: 1600, height: 1081, source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311pl.jpg")!
check(abs(crop.x - 855) <= 2 && abs(crop.width - 745) <= 2, "jacket front crop matches the ps (\(crop))")
check(DMMImageValidation.frontCrop(width: 745, height: 1081) == nil, "portrait not cropped")

// ---- probe policy
check(DMMProbePolicy.shouldRetry(status: nil) && DMMProbePolicy.shouldRetry(status: 503) && DMMProbePolicy.shouldRetry(status: 429), "retry transient")
check(!DMMProbePolicy.shouldRetry(status: 404) && !DMMProbePolicy.shouldRetry(status: 200), "404 is definitive")
check(DMMProbePolicy.backoff(1) > DMMProbePolicy.backoff(0) && DMMProbePolicy.concurrency <= 3 && DMMProbePolicy.negativeTTL <= 600, "backoff + small concurrency + short negative TTL")

// ---- winner: DMM portrait beats the JavDB jacket crop; provenance DMM
let dmm = DetailPosterQuality(source: milk[0], width: 745, height: 1081, originalPortrait: true)
let dmmCrop = DetailPosterQuality(source: milk[1], width: 746, height: 1081, originalPortrait: false)
let javdb = DetailPosterQuality(source: "https://c0.jdbstatic.com/covers/zn/ZN0deq.jpg", width: 378, height: 541, originalPortrait: false)
let win = DetailPosterQuality.winner([javdb, dmmCrop, dmm])!
check(win.source == milk[0], "MILK-311 winner is the DMM ps")
check(PosterProvenance(source: win.source).text == "封面来源：DMM", "封面来源：DMM")
check(DetailPosterQuality.winner([javdb, dmmCrop])!.source == milk[1], "pl crop beats JavDB when ps is missing")
print("PASS dmm282: CID resolver (seed/learned/exact/pad), persistence + caps, URL patterns + admission, upgrades, placeholders, crop, probe policy, MILK-311 winner → 封面来源：DMM")
