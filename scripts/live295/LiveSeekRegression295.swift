// Build 295 — seek teardown / reopen gate + first-open play gate (pure LiveSeekPolicy).
import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) {
    if !c() { failures += 1; print("FAIL", m) } else { print("PASS", m) }
}

let S = LiveSeekPolicy.self
check(S.coalesceNanoseconds == 450_000_000, "293 coalesce floor kept")
check(S.playReadyTimeoutSeconds >= 1.5 && S.playReadyTimeoutSeconds <= 3.0, "play-ready timeout ~2s")
check(S.firstOpenPlayGateSeconds >= 1.0 && S.firstOpenPlayGateSeconds <= 2.5, "first-open gate ~1.5s")
check(S.mayReopen(playerReady: true, playing: false, elapsedSinceCoalesce: 0), "playerReady opens")
check(S.mayReopen(playerReady: false, playing: true, elapsedSinceCoalesce: 0), "playing opens")
check(!S.mayReopen(playerReady: false, playing: false, elapsedSinceCoalesce: 0.5), "too early blocked")
check(S.mayReopen(playerReady: false, playing: false, elapsedSinceCoalesce: S.playReadyTimeoutSeconds), "timeout opens")
check(S.mayFirstOpen(playing: true, elapsed: 0), "playing passes first-open")
check(!S.mayFirstOpen(playing: false, elapsed: 0.2), "cold open waits")
check(S.mayFirstOpen(playing: false, elapsed: S.firstOpenPlayGateSeconds), "first-open timeout")

// 294 catch-up still intact
let P = LiveCatchUpPolicy.self
check(P.reopenGraceSeconds >= 20, "294 grace kept")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 100, lastCatchUp: 0, graceUntil: 110, decodedGrowing: false) == .none,
      "grace still blocks catch-up")

if failures == 0 { print("ALL PASS 295 seek-policy") } else { print("FAILED \(failures)"); exit(1) }
