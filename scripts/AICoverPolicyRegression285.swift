import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) { if !c() { failures += 1; print("FAIL", m) } }

// Eligibility: only low-res NATIVE fronts; HQ originals are never enhanced.
check(AICoverEnhancePolicy.eligible(source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ipx00706/ipx00706pl.jpg", nativeWidth: 378, nativeHeight: 538), "800 px jacket crop eligible")
check(AICoverEnhancePolicy.eligible(source: "https://image.mgstage.com/images/x/pf_e_x-1.jpg", nativeWidth: 422, nativeHeight: 600), "MGS pf_e eligible")
check(AICoverEnhancePolicy.eligible(source: "https://c0.jdbstatic.com/covers/pr/pRX45.jpg", nativeWidth: 376, nativeHeight: 538), "JavDB fallback eligible")
check(!AICoverEnhancePolicy.eligible(source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00181/ssis00181ps.jpg", nativeWidth: 1032, nativeHeight: 1468), "DMM HQ ps never enhanced")
check(!AICoverEnhancePolicy.eligible(source: "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311ps.jpg", nativeWidth: 745, nativeHeight: 1081), "MILK 745×1081 never enhanced")
check(!AICoverEnhancePolicy.eligible(source: "fixture://neutral", nativeWidth: 378, nativeHeight: 538), "neutral fixture never enhanced")
check(!AICoverEnhancePolicy.eligible(source: "x", nativeWidth: 0, nativeHeight: 0), "unknown native size never enhanced")
check(!AICoverEnhancePolicy.eligible(source: "x", nativeWidth: 147, nativeHeight: 200), "thumbnail below minimum")

// Guard
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: false, battery: 0.8, charging: false) == .ok, "auto ok")
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: false, battery: 0.8, charging: false) == .ok, "auto ok when hot (289: no thermal gating)")
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: true, battery: 0.8, charging: false) == .lowPower, "auto low power")
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: false, battery: 0.1, charging: false) == .lowBattery, "auto low battery")
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: false, battery: 0.1, charging: true) == .ok, "charging ok")
check(AICoverEnhanceGuard.verdict(manual: false, lowPower: false, battery: -1, charging: false) == .ok, "unknown battery (simulator) ok")
check(AICoverEnhanceGuard.verdict(manual: true, lowPower: true, battery: 0.05, charging: false) == .ok, "manual ignores battery")
check(AICoverEnhanceGuard.verdict(manual: true, lowPower: false, battery: 1, charging: true) == .ok, "manual ok when critical (289: no thermal gating)")
check(AICoverEnhanceGuard.message(.lowPower) != nil && AICoverEnhanceGuard.message(.ok) == nil, "messages")

// Modes
check(AICoverEnhanceMode.allCases.map(\.title) == ["自动", "仅手动", "关"], "mode titles")

// Tiling covers every pixel, edges exact, overlap ≥ 2·12 between neighbours.
for (len, tile) in [(378, 128), (538, 128), (600, 128), (422, 128), (100, 128), (128, 128), (129, 128)] {
    let o = AICoverTilePlan.make(length: len, tile: tile, overlap: 12).origins
    check(o.first == 0, "starts at 0 \(len)")
    if len > tile {
        check(o.last! + tile == len, "ends at edge \(len)")
        for (a, b) in zip(o, o.dropFirst()) { check(b > a && a + tile - b >= 24 || b == len - tile && b > a, "overlap \(len) \(a)->\(b)") }
    } else { check(o == [0], "single padded tile \(len)") }
}
check(AICoverTilePlan.make(length: 378, tile: 128, overlap: 12).origins.count == 4, "378 → 4 columns")
check(AICoverTilePlan.make(length: 538, tile: 128, overlap: 12).origins.count == 5, "538 → 5 rows")
let s1 = AICoverSRSize.output(width: 378, height: 538, scale: 4)
check(s1.width == 1512 && s1.height == 2152, "378×538 ×4 → 1512×2152 \(s1)")
let s2 = AICoverSRSize.output(width: 422, height: 600, scale: 4)
check(s2.height == 2160 && s2.width == 1519, "422×600 capped at 2160 \(s2)")
if failures == 0 { print("PASS ai285 policy: eligibility (HQ never), thermal/battery guard, modes, tiling coverage, output size cap") } else { exit(1) }
