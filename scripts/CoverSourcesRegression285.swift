import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) { if !c() { failures += 1; print("FAIL", m) } }

// Crop ratio: right-aligned 0.703·h; MILK (h_1240) keeps 0.69.
let ipx = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706pl.jpg"
let milk = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311pl.jpg"
let c1 = DMMImageValidation.frontCrop(width: 800, height: 538, source: ipx)!
check(c1.width == 378 && c1.x == 422, "IPX 800×538 → 378 @422 \(c1)")
let c2 = DMMImageValidation.frontCrop(width: 2184, height: 1468, source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00181/ssis00181pl.jpg")!
check(c2.width == 1032, "2184×1468 front = 1032 (= native ps width) \(c2)")
let c3 = DMMImageValidation.frontCrop(width: 1600, height: 1081, source: milk)!
check(c3.width == 746 || c3.width == 745, "MILK keeps 0.69 \(c3)")

// Jacket-only learning (isolated defaults)
let suite = UserDefaults(suiteName: "avdb.test285.\(UUID().uuidString)")!
let store = DMMJacketOnly(defaults: suite)
let ps = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706ps.jpg"
check(store.filter([ps, ipx]) == [ps, ipx], "unknown cid keeps ps")
store.observe(source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00181/ssis00181ps.jpg", width: 1032, height: 1468)
check(!store.contains("ssis00181"), "real portrait never learned")
store.observe(source: ps, width: 147, height: 200)
check(store.contains("ipx00706"), "147×200 ps learned")
check(store.filter([ps, ipx]) == [ipx], "known jacket-only skips ps, keeps pl")
check(DMMJacketOnly(defaults: suite).contains("ipx00706"), "persisted across instances")
check(!store.contains("ipx00706", now: Date().addingTimeInterval(DMMJacketOnly.ttl + 60)), "TTL expiry re-probes ps")

// DUGA provenance + official rank
let duga = "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg"
check(PosterProvenance(source: duga).text == "封面来源：DUGA", "DUGA label")
let dq = DetailPosterQuality(source: duga, width: 474, height: 674, originalPortrait: false)
let dmmq = DetailPosterQuality(source: ipx, width: 378, height: 538, originalPortrait: false)
check(DetailPosterQuality.winner([dmmq, dq])!.source == duga, "DUGA 1000 px jacket beats the 800 px DMM jacket")
let javdb = DetailPosterQuality(source: "https://c0.jdbstatic.com/covers/pr/pRX45.jpg", width: 376, height: 538, originalPortrait: false)
check(DetailPosterQuality.winner([javdb, dmmq])!.source == ipx, "DMM 378 beats JavDB 376")
if failures == 0 { print("PASS cover285: 0.703 crop (MILK 0.69), persistent jacket-only ps skip with TTL, DUGA provenance/rank") } else { exit(1) }
