// Build 294 — catch-up grace / soft vs hard / hitch-aware jump detect (pure LiveCatchUpPolicy + softReopen).
import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) {
    if !c() { failures += 1; print("FAIL", m) } else { print("PASS", m) }
}

let P = LiveCatchUpPolicy.self

check(P.action(playing: true, decodedEnd: 10, playhead: 12, now: 100, lastCatchUp: 0, graceUntil: 0, decodedGrowing: false) == .none,
      "not behind enough")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 100, lastCatchUp: 0, graceUntil: 0, decodedGrowing: false) == .soft(gap: 10),
      "soft when modestly behind")
check(P.action(playing: true, decodedEnd: 10, playhead: 50, now: 100, lastCatchUp: 0, graceUntil: 0, decodedGrowing: false) == .hard(gap: 40),
      "hard when far behind")
check(P.action(playing: false, decodedEnd: 10, playhead: 50, now: 100, lastCatchUp: 0, graceUntil: 0, decodedGrowing: false) == .none,
      "paused skips catch-up")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 100, lastCatchUp: 95, graceUntil: 0, decodedGrowing: false) == .none,
      "cooldown blocks")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 100, lastCatchUp: 0, graceUntil: 110, decodedGrowing: false) == .none,
      "reopen grace blocks")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 100, lastCatchUp: 0, graceUntil: 0, decodedGrowing: true) == .none,
      "decoded still growing waits")
check(P.action(playing: true, decodedEnd: 10, playhead: 20, now: 111, lastCatchUp: 0, graceUntil: 110, decodedGrowing: false) == .soft(gap: 10),
      "after grace expires soft again")

check(!P.isMediaJump(delta: 1.6, hitchRecent: false), "1.6s no longer a seek (was 1.5)")
check(P.isMediaJump(delta: 3.0, hitchRecent: false), "3s is a seek")
check(!P.isMediaJump(delta: 3.0, hitchRecent: true), "3s after hitch ignored")
check(P.isMediaJump(delta: 9.0, hitchRecent: true), "9s after hitch still a scrub")

do {
    let pipe = LivePipeline()
    let g0 = pipe.currentGeneration
    pipe.reset(at: 0)
    check(pipe.snapshotStats.decodedEnd == 0, "reset decodedEnd")
    check(pipe.currentGeneration == g0 + 1, "reset bumps generation")
    pipe.softReopen(at: 5)
    check(pipe.snapshotStats.decodedEnd == 5, "softReopen decodedEnd")
    check(pipe.currentGeneration == g0 + 2, "softReopen bumps generation")
}

check(P.reopenGraceSeconds >= 20 && P.reopenGraceSeconds <= 25, "grace 20–25s")
check(P.softGapLimit >= 25 && P.softGapLimit <= 30, "soft gap ~25–30s")
check(P.jumpThreshold > 1.5, "jump threshold raised")

if failures == 0 { print("ALL PASS 294 catch-up") } else { print("FAILED \(failures)"); exit(1) }
