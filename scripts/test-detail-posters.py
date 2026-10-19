"""Compile and run the actual production policy/cache; no supplied JS executes."""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
policy=(root/'AVDB/Services/DetailPosterPolicy.swift').read_text()
cache=(root/'AVDB/Services/DetailPosterCache.swift').read_text()
tests=r'''
actor Count {
    var calls=0; var cancelled=0
    func hit() { calls += 1 }
    func cancel() { cancelled += 1 }
    func snapshot() -> (Int,Int) { (calls,cancelled) }
}
actor SelectionHarvestGate {
    private var lowHarvested = false
    func signalLowHarvested() { lowHarvested = true }
    func waitForLowHarvest() async {
        while !lowHarvested && !Task.isCancelled { await Task.yield() }
    }
}
actor SelectionProbe {
    var active=0; var peak=0; var calls=0
    func start() { active += 1; calls += 1; peak=max(peak,active) }
    func end() { active -= 1 }
    func snapshot() -> (Int,Int,Int) { (calls,peak,active) }
}
@main struct Main {
 static func main() async {
    assert(DetailPosterPolicy.candidates(number:"ABF-378") == [
        "https://image.mgstage.com/images/prestige/abf/378/pf_e_abf-378.jpg",
        "https://image.mgstage.com/images/prestige/abf/378/pf_o1_abf-378.jpg"])
    assert(DetailPosterPolicy.candidates(number:"390JAC-012").first == "https://image.mgstage.com/images/jackson/390jac/12/pf_e_390jac-12.jpg")
    assert(DetailPosterPolicy.candidates(number:"ABF-001").contains("https://image.mgstage.com/images/prestige/abf/001/pf_o1_abf-001.jpg"))
    assert(DetailPosterPolicy.candidates(number:"STARS-001").first == "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/1stars00001/1stars00001ps.jpg")
    for number in ["title ABF-378", "ABF-378-U", "FC2-PPV-1234567", "ABF-378 / ABF-379", "../ABF-378", "ABF-000"] {
        assert(DetailPosterPolicy.candidates(number:number).isEmpty,number)
    }
    assert(!DetailPosterPolicy.eligible(width:147,height:200))
    assert(!DetailPosterPolicy.eligible(width:800,height:538))
    assert(!DetailPosterPolicy.eligible(width:359,height:800))
    assert(DetailPosterPolicy.eligible(width:376,height:538))
    assert(DetailPosterPolicy.eligible(width:700,height:1000))
    for bad in ["https://pics.dmm.co.jp.evil.test/digital/video/x/xps.jpg", "http://pics.dmm.co.jp/digital/video/x/xps.jpg", "https://user@pics.dmm.co.jp/digital/video/x/xps.jpg", "https://pics.dmm.co.jp/digital/video/x/xpl.jpg", "https://pics.dmm.co.jp/digital/video/x/xps.jpg?token=anything"] {
        assert(!DetailPosterPolicy.allowedPublicImage(URL(string:bad)!))
    }
    let c=DetailPosterCache<Int>(positiveTTL:0.15,negativeTTL:0.05)
    let count=Count()
    let op: @Sendable () async -> Int? = {
        await count.hit()
        do { try await Task.sleep(nanoseconds:40_000_000); return 7 }
        catch { await count.cancel(); return nil }
    }
    async let a=c.value(key:"account-A/movie-1",operation:op)
    async let b=c.value(key:"account-A/movie-1",operation:op)
    let values=await (a,b); assert(values.0 == 7 && values.1 == 7)
    var snap=await count.snapshot(); assert(snap.0 == 1)
    let cached=await c.value(key:"account-A/movie-1",operation:op); assert(cached == 7)
    snap=await count.snapshot(); assert(snap.0 == 1)
    _=await c.value(key:"account-B/movie-1",operation:op)
    snap=await count.snapshot(); assert(snap.0 == 2) // account isolation
    try? await Task.sleep(nanoseconds:180_000_000)
    _=await c.value(key:"account-A/movie-1",operation:op)
    snap=await count.snapshot(); assert(snap.0 == 3) // TTL revalidation
    let failure=Count()
    let fail: @Sendable () async -> Int? = { await failure.hit(); return nil }
    _=await c.value(key:"fail",operation:fail); _=await c.value(key:"fail",operation:fail)
    snap=await failure.snapshot(); assert(snap.0 == 1)
    try? await Task.sleep(nanoseconds:70_000_000)
    _=await c.value(key:"fail",operation:fail)
    snap=await failure.snapshot(); assert(snap.0 == 2)
    let cancelled=Count()
    let slow: @Sendable () async -> Int? = {
        await cancelled.hit()
        do { try await Task.sleep(nanoseconds:500_000_000); return 9 }
        catch { await cancelled.cancel(); return nil }
    }
    let task=Task { await c.value(key:"cancel",operation:slow) }
    try? await Task.sleep(nanoseconds:30_000_000); task.cancel()
    let cancelledResult=await task.value; assert(cancelledResult == nil)
    snap=await cancelled.snapshot(); assert(snap.1 == 1)
    // A cancelled old flight must neither cache failure nor overwrite a fresh result.
    let fresh=await c.value(key:"cancel",operation:op); assert(fresh == 7)
    let survivor=Count()
    let shared: @Sendable () async -> Int? = {
        await survivor.hit()
        do { try await Task.sleep(nanoseconds:120_000_000); return 11 }
        catch { await survivor.cancel(); return nil }
    }
    let first=Task { await c.value(key:"shared",operation:shared) }
    let second=Task { await c.value(key:"shared",operation:shared) }
    try? await Task.sleep(nanoseconds:30_000_000); first.cancel()
    let result=await second.value; assert(result == 11)
    snap=await survivor.snapshot(); assert(snap.0 == 1 && snap.1 == 0)
    let generation=UUID()
    var presentation=DetailPosterPresentation<Int>(key:"new/account",generation:generation,layout:.resolving)
    presentation.complete(1,key:"old/account",generation:generation)
    assert(presentation.layout.artwork == nil)
    presentation.complete(2,key:"new/account",generation:UUID())
    assert(presentation.layout.artwork == nil)
    presentation.complete(7,key:"new/account",generation:generation)
    presentation.complete(9,key:"new/account",generation:generation)
    assert(presentation.layout.artwork == 7)
    assert(c.snapshot(key:"unknown").artwork == nil && !c.snapshot(key:"unknown").isLandscape)
    _=await c.value(key:"fail",operation:fail)
    assert(c.snapshot(key:"fail").isLandscape)
    let low=DetailPosterQuality(source:"low",width:376,height:538,originalPortrait:false)
    let high=DetailPosterQuality(source:"high",width:700,height:1000,originalPortrait:true)
    let gate = SelectionHarvestGate()
    let start=ProcessInfo.processInfo.systemUptime
    let collected: [DetailPosterQuality] = await DetailPosterSelection.collect(sources:["low","high","fail","late"],budget:0.12) { source, _ in
        if source == "low" { return low }
        if source == "high" {
            // "fail" cannot start until the collector has harvested low and
            // released its concurrency slot. Prove low-first/high-later by
            // scheduler causality instead of a loaded runner's 5/40ms sleeps.
            await gate.waitForLowHarvest()
            return Task.isCancelled ? nil : high
        }
        if source == "fail" { await gate.signalLowHarvested(); return nil }
        do { try await Task.sleep(nanoseconds:1_000_000_000) }
        catch { return nil }
        return nil
    }
    assert(ProcessInfo.processInfo.systemUptime-start < 0.5)
    assert(collected.count == 2 && DetailPosterQuality.winner(collected)?.source == "high", "collected=\(collected.map(\.source))")
    assert(collected.first?.source == "low", "High must only complete after low is actually harvested")
    assert(DetailPosterSelection.maxAttempts == 6 && DetailPosterSelection.concurrency == 2 && DetailPosterSelection.totalBudget == 12)
    let probe=SelectionProbe()
    let bounded: [String] = await DetailPosterSelection.collect(sources:["a","a","b","c","d","e","f","g","h"],budget:0.3) { source, timeout in
        assert(timeout > 0 && timeout <= 5)
        await probe.start()
        try? await Task.sleep(nanoseconds:10_000_000)
        await probe.end()
        return source
    }
    let limits=await probe.snapshot()
    assert(bounded.count == 6 && Set(bounded).count == 6)
    assert(limits.0 == 6 && limits.1 == 2 && limits.2 == 0)
    let empty: [Int] = await DetailPosterSelection.collect(sources:[]) { _,_ in 1 }
    assert(empty.isEmpty)
    print("PASS actual Swift detail poster layout one-shot, stale movie/generation, budget cancellation, low-first high-later, provider rules, account isolation, dedup, TTL and negative cache")
 }
}
'''
# User-requested recovery: original fill hero and original action strip, not build191.
detail=(root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
settings=(root/'AVDB/Views/User/UserView.swift').read_text()
portrait=detail.split('private func portraitHero',1)[1].split('private func posterAction',1)[0]
for literal in ['scaledToFill()', 'width * 1.58', 'width * 0.99', 'location: 0.36', 'location: 0.86', 'HStack(spacing: 28)', '.background(.clear, in: RoundedRectangle(cornerRadius: 17))', '.frame(width: 44, height: 44)', 'if showCoverTitle', 'DetailReadableTitle']:
    assert literal in portrait,literal
assert 'LazyVGrid' not in portrait  # The unrelated screenshots gallery remains a grid.
for forbidden in ['DetailActionGlass', 'detailActions(movie)', 'glassEffect(']:
    assert forbidden not in detail,forbidden
assert 'lineLimit(expanded ? nil : 3)' in detail
assert 'truncated = (heights["full"] ?? 0) > (heights["three"] ?? 0) + 1' in detail
assert '.hidden().accessibilityHidden(true).allowsHitTesting(false)' in detail
assert '@AppStorage("detail.showCoverTitle") private var showCoverTitle = true' in detail
assert '@AppStorage("detail.showCoverTitle") private var showCoverTitle = true' in settings
assert 'Toggle("显示封面标题", isOn: $showCoverTitle)' in settings
print('PASS restored fill hero, white play, original 44pt action strip, three-line disclosure and persistent visibility wiring')
# Ensure the detail-only resolver really keeps auth/session and bounds in production.
resolver=(root/'AVDB/Services/DetailPosterResolver.swift').read_text()
for literal in ['URLSessionConfiguration.ephemeral','config.httpCookieStorage = nil','config.httpShouldSetCookies = false','config.urlCredentialStorage = nil','DetailPosterSelection.collect','12 * 1024 * 1024','Task.checkCancellation()','SHA256.hash','CGImageSourceCopyPropertiesAtIndex','kCGImageSourceCreateThumbnailWithTransform','rules.contains(source)','target.path == path','target.query == nil']:
    assert literal in resolver,literal
assert 'Pan115Client' not in resolver and 'Cookie"' not in resolver and 'Authorization"' not in resolver
setup=(root/'scripts/setup-poster-uitests.rb').read_text()
assert "c.build_settings['OTHER_LDFLAGS'] = '-Wl,-no_warn_duplicate_libraries'" in setup # no duplicate MediaPipe force_load in hosted test
if not shutil.which('swiftc'):
    print('PASS static safety checks; actual Swift execution requires macOS CI')
else:
    with tempfile.TemporaryDirectory() as td:
        dependencies = '\n'.join((root/'AVDB/Services'/f).read_text() for f in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift'])
        p=Path(td); (p/'main.swift').write_text(dependencies+'\n'+policy+'\n'+cache+'\n'+tests)
        subprocess.run(['swiftc','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True,timeout=30)

# Build-ipa already executes this entry point: new JavBus Swift regressions are
# mandatory on the same macOS runner, not merely an unreferenced test script.
subprocess.run([__import__('sys').executable,str(root/'scripts/test-javbus-posters.py')],check=True)
