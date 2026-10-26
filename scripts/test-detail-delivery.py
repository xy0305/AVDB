"""Build220: controlled native production delivery/selection/cache measurements.
Transport delays are deterministic test inputs, NOT public network speed claims.
"""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
read=lambda p:(root/p).read_text()
sdk=read('AVDB/Services/JavDBSDK.swift'); view=read('AVDB/Views/Detail/MovieDetailView.swift'); resolver=read('AVDB/Services/DetailPosterResolver.swift'); metadata=read('AVDB/Services/CatalogueMetadata.swift')
assert 'DetailMetadataDelivery.complete(native: data, onNative: onNative)' in sdk
assert 'sdk.movieDetailFull(movieID, onNative:' in view
assert 'posterSeed ?? vm.posterMovie ?? vm.movie' in view
assert 'if self.posterMovie == nil { self.posterMovie = native.movie }' in view
assert 'self.loadGeneration == generation' in view and 'APIClient.shared.token == account' in view
assert 'DetailPosterCache<ScrapedMetadata>' in metadata and 'return await cache.value(key: key)' in metadata
assert 'async let tenhow' in resolver and 'async let metadata' in resolver
core='\n'.join(read('AVDB/Services/'+f) for f in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift','DetailPosterPolicy.swift','DetailPosterCache.swift'])
swift=r'''
actor DeliveryProbe {
 var nativeTime=0.0; var winnerTime=0.0; var metadataCalls=0; var imageCalls=0
 var winner: String?; var poster: Task<Void,Never>?
 var metadataFinished=false; var nativeBeforeMetadata=false; var imageBeforeMetadata=false
 func native() { nativeTime=ProcessInfo.processInfo.systemUptime; nativeBeforeMetadata = !metadataFinished }
 func metadata() { metadataCalls += 1 }
 func finishMetadata() { metadataFinished=true }
 func waitForImage() async { while imageCalls == 0 && !Task.isCancelled { await Task.yield() } }
 func image() { if imageCalls == 0 { imageBeforeMetadata = !metadataFinished }; imageCalls += 1 }
 func ordering() -> (Bool,Bool) { (nativeBeforeMetadata,imageBeforeMetadata) }
 func result(_ source: String?) { winner=source; winnerTime=ProcessInfo.processInfo.systemUptime }
 func launch(_ work: @escaping @Sendable () async -> Void) { poster=Task { await work() } }
 func join() async { await poster?.value }
 func values() -> (Double,Double,Int,Int,String?) { (nativeTime,winnerTime,metadataCalls,imageCalls,winner) }
}
actor DeliveryGate {
 var released=false
 func open() { released=true }
 func wait() async -> Bool {
  while !released && !Task.isCancelled { await Task.yield() }
  return !Task.isCancelled
 }
}
@main struct DeliveryRegression {
 static func run(early: Bool) async -> [String:Any] {
  let p=DeliveryProbe(); let metadata=DetailPosterCache<Int>(positiveTTL:3600,negativeTTL:300,capacity:128)
  let artwork=DetailPosterCache<String>(); let key="account-A#real-id#same-sources"
  let begin=ProcessInfo.processInfo.systemUptime
  let lookup: @Sendable () async -> Int? = {
   await metadata.value(key:"ABF-378#avbase") {
    await p.metadata()
    // Deterministic overlap rendezvous, not a race between two CI wall clocks.
    // A regression to serial delivery deadlocks here and fails the process timeout.
    if early { await p.waitForImage() }
    do { try await Task.sleep(nanoseconds:180_000_000); await p.finishMetadata(); return 1 } catch { return nil }
   }
  }
  let select: @Sendable () async -> Void = {
   let winner=await artwork.value(key:key) {
    let values:[DetailPosterQuality]=await DetailPosterSelection.collect(sources:["javdb","mgs"],discover:{ _ in
     _=await lookup(); return ["tenhow","amazon"]
    }) { source,_ in
     await p.image()
     do { try await Task.sleep(nanoseconds:source == "javdb" ? 100_000_000 : 10_000_000) } catch { return nil }
     return DetailPosterQuality(source:source,width:source == "amazon" ? 1050:700,height:source == "amazon" ? 1500:1000,originalPortrait:true)
    }
    return DetailPosterQuality.winner(values)?.source
   }
   await p.result(winner)
  }
  let observer: ((Int) async -> Void)? = early ? { _ in await p.native(); await p.launch(select) } : nil
  let enriched=await DetailMetadataDelivery.complete(native:0,onNative:observer) { _ in _=await lookup(); return 1 }
  assert(enriched == 1)
  if !early { await p.native(); await p.launch(select) }
  await p.join()
  let v=await p.values()
  let ordering=await p.ordering()
  assert(ordering.0 == early && ordering.1 == early, "native delivery and image work must overlap metadata iff early delivery is enabled")
  assert(v.2 == 1 && v.3 == 4 && v.4 == "amazon")
  let warmBegin=ProcessInfo.processInfo.systemUptime
  assert(artwork.snapshot(key:key).artwork == "amazon")
  let warm=await artwork.value(key:key) { fatalError("warm winner fetched again") }
  assert(warm == "amazon")
  assert(artwork.snapshot(key:"account-B#real-id#same-sources").artwork == nil)
  assert(artwork.snapshot(key:"account-A#other-id#same-sources").artwork == nil)
  let after=await p.values();assert(after.2 == 1 && after.3 == 4)
  return ["native_first_display_ms":(v.0-begin)*1000,"stable_hq_winner_ms":(v.1-begin)*1000,"warm_winner_ms":(ProcessInfo.processInfo.systemUptime-warmBegin)*1000,"metadata_requests":v.2,"image_attempts":v.3,"winner":v.4!,"winner_native_pixels":[1050,1500]]
 }
 static func main() async {
  let before=await run(early:false); let after=await run(early:true)
  print("DELIVERY220_TIMING before=\(before) after=\(after)")
  // Independent runs on a shared runner are not an ordering oracle (old line
  // 2959 compared ~290ms vs ~190ms with zero scheduling tolerance). Causal
  // ordering is asserted inside run; retain a separate bounded latency gate.
  assert((after["stable_hq_winner_ms"] as! Double) < 5_000, "correct HQ selection exceeded correctness budget")
  assert((after["native_first_display_ms"] as! Double) < 500, "early native delivery blocked on metadata")
  // Leased metadata lookup: cancelling the detail consumer keeps the poster
  // consumer alive; cancelling the last consumer cancels I/O without a miss.
  let cache=DetailPosterCache<Int>();let probe=DeliveryProbe();let gate=DeliveryGate()
  let work: @Sendable () async -> Int? = {
   await probe.metadata()
   return await gate.wait() ? 9 : nil
  }
  let a=Task { await cache.value(key:"shared",operation:work) }
  let b=Task { await cache.value(key:"shared",operation:work) }
  while cache.fixtureLeaseCount(key:"shared") != 2 { await Task.yield() }
  a.cancel();await gate.open()
  let survivor=await b.value;let cancelled=await a.value
  assert(survivor == 9 && cancelled == nil)
  let v=await probe.values();assert(v.2 == 1)
  let start=ProcessInfo.processInfo.systemUptime
  let c=Task { await cache.value(key:"last") {
   do { try await Task.sleep(nanoseconds:5_000_000_000); return 8 } catch { return nil }
  } }
  while cache.fixtureLeaseCount(key:"last") != 1 { await Task.yield() }
  c.cancel()
  let cancelledLast=await c.value;assert(cancelledLast == nil)
  assert(!cache.snapshot(key:"last").isLandscape)
  let cancelMS=(ProcessInfo.processInfo.systemUptime-start)*1000
  assert(cancelMS < 500)
  let output:[String:Any] = ["kind":"controlled-native-production-not-live-network","transport_inputs_ms":["metadata":180,"javdb":100,"other_images":10],"before219_serial_gate":before,"after220_native_delivery":after,"last_lease_cancel_ms":cancelMS,"identity_isolation":"account and movie miss; same Amazon winner, same native pixels, no low-res reuse","coalescing":"one metadata operation for detail + poster; one cancelled lease preserves survivor"]
  let data=try! JSONSerialization.data(withJSONObject:output,options:[.sortedKeys])
  print("PERFORMANCE220_JSON "+String(data:data,encoding:.utf8)!)
  print("PASS native production early delivery, identical HQ winner, metadata dedup, synchronous warm winner, cancellation and identity isolation")
 }
}
'''
if shutil.which('swiftc'):
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'main.swift').write_text(core+'\n'+swift)
  subprocess.run(['swiftc','-D','DEBUG','-swift-version','5','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
  subprocess.run([str(p/'test')],check=True,timeout=20)
else:
 print('PASS build220 source integration; SKIP native timing: requires macOS Swift CI')
