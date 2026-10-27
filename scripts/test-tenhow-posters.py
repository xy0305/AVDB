"""Run production Tenhow parser/mapping and shared scheduler, not a Python reimplementation."""
from pathlib import Path
import shutil, subprocess, tempfile, json
root=Path(__file__).resolve().parents[1]
services=root/'AVDB/Services'
resolver=(services/'DetailPosterResolver.swift').read_text()
for s in ['TenhowPoster.pages','actor.name, actor.otherName, actor.keyword','movie.actorNames','tenhowPaths(movie)','discover: discover','positiveTTL: 6 * 3600, negativeTTL: 300','namespace + path','768 * 1024','config.httpCookieStorage = nil','config.urlCredentialStorage = nil','AmazonPoster.directHQ','MAIN._SCRM_']:
    assert s in resolver,s
assert 'displayName' not in resolver.replace('// actor_names is the API\'s original identity fallback, never UI displayName.','')
core='\n'.join((services/f).read_text() for f in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift','DetailPosterPolicy.swift','DetailPosterCache.swift'])
tests=r'''
actor Probe {
 var active=0; var peak=0; var calls=0
 func start() { active += 1; calls += 1; peak=max(peak,active) }
 func end() { active -= 1 }
 func snapshot() -> (Int,Int,Int) { (active,peak,calls) }
 func waitForInitialCompletions() async {
  while (calls < 2 || active > 0) && !Task.isCancelled { await Task.yield() }
 }
}
@main struct Main {
 static func main() async throws {
  let fixtures=URL(fileURLWithPath:CommandLine.arguments[1])
  let evidence=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtures.appendingPathComponent("evidence.json"))) as! [[String:Any]]
  for item in evidence {
   let html=try String(contentsOf:fixtures.appendingPathComponent(item["fixture"] as! String),encoding:.utf8)
   let urls=try TenhowPoster.images(html:html,number:item["number"] as! String)
   assert(urls == [item["url"] as! String], "real fixture \(item["number"]!) \(urls)")
   assert(try TenhowPoster.images(html:html,number:"ZZZZ-99999").isEmpty)
  }
  assert(TenhowActorLinks.paths.count >= 1700)
  assert(TenhowPoster.pages(identities:[["蓮実クレア"]]) == ["/hasumi_kurea.html"])
  assert(TenhowPoster.pages(identities:[["蓮見クレア"]]) == ["/hasumi_kurea.html"])
  assert(TenhowPoster.pages(identities:[["not known"]]).isEmpty)
  assert(TenhowPoster.pages(identities:[["蓮実クレア","JULIA"]]).isEmpty)
  assert(TenhowPoster.pages(identities:[["same"]],mapping:["same":["/julia.html","/hasumi_kurea.html"]]).isEmpty)
  assert(TenhowPoster.cid("meyd00575") == "meyd-575")
  assert(TenhowPoster.cid("meyd575") == "meyd-575")
  assert(TenhowPoster.cid("1stars00001") == "stars-1")
  assert(TenhowPoster.cid("h_346rebd00123") == "rebd-123")
  for cid in ["1meyd00575","118meyd575","meyd575x","meyd00000","xmeyd575/","meyd575/meyd576"] { assert(TenhowPoster.cid(cid) == nil) }
  for code in ["MEYD-575 / MEYD-576","title MEYD-575","MEYD-575U","FC2-PPV-12345"] { assert(TenhowPoster.number(code) == nil) }
  func record(_ asin:String,_ cids:[String]) -> String {
   let links=cids.map { "<a href='https://al.fanza.co.jp/?lurl=https%3A%2F%2Fwww.dmm.co.jp%2Fmono%2Fdvd%2F-%2Fdetail%2F%3D%2Fcid%3D\($0)%2F&amp;af_id=x'>DVD</a>" }.joined()
   return "<div class='um_image_a um_popup'><a title='拡大表示' href='images/\(asin).jpg'>image</a><div class='buythis'>\(links)</div></div>"
  }
  let good=record("B084SXDZYQ",["meyd575","meyd00575"])
  let other=record("B07D2PKM33",["meyd388"])
  assert(try TenhowPoster.images(html:other+good,number:"MEYD-575") == ["https://www.tenhow.net/images/B084SXDZYQ.jpg"])
  assert(try TenhowPoster.images(html:other,number:"MEYD-575").isEmpty)
  assert(try TenhowPoster.images(html:record("B084SXDZYQ",["meyd575","meyd576"]),number:"MEYD-575").isEmpty)
  assert(try TenhowPoster.images(html:good+record("B00RT0JR3U",["meyd575"]),number:"MEYD-575").isEmpty)
  assert(try TenhowPoster.images(html:good.replacingOccurrences(of:"images/B084",with:"images/icon_B084"),number:"MEYD-575").isEmpty)
  assert(try TenhowPoster.images(html:good.replacingOccurrences(of:"images/B084",with:"https://evil.test/images/B084"),number:"MEYD-575").isEmpty)
  assert(try TenhowPoster.images(html:good.replacingOccurrences(of:"meyd00575",with:"1meyd00575"),number:"MEYD-575").isEmpty)
  for bad in ["http://www.tenhow.net/images/B084SXDZYQ.jpg","https://tenhow.net/images/B084SXDZYQ.jpg","https://www.tenhow.net.evil.test/images/B084SXDZYQ.jpg","https://user@www.tenhow.net/images/B084SXDZYQ.jpg","https://www.tenhow.net/images/s_B084SXDZYQ.jpg","https://www.tenhow.net/images/B084SXDZYQ.jpg?q=1","https://www.tenhow.net/images/%42084SXDZYQ.jpg"] { assert(!TenhowPoster.allowedImage(URL(string:bad)!)) }
  let from=URL(string:"https://www.tenhow.net/hasumi_kurea.html")!
  assert(TenhowPoster.permitsRedirect(from:from,to:from))
  for bad in ["https://evil.test/hasumi_kurea.html","https://www.tenhow.net/julia.html","https://www.tenhow.net/hasumi_kurea.html?q=1","http://www.tenhow.net/hasumi_kurea.html"] { assert(!TenhowPoster.permitsRedirect(from:from,to:URL(string:bad)!)) }
  assert(!TenhowPoster.allowedPage("/made_up_actor.html"))
'''
tests += r'''
  let probe=Probe()
  let low=DetailPosterQuality(source:"old",width:376,height:538,originalPortrait:false)
  let high=DetailPosterQuality(source:"tenhow",width:1055,height:1500,originalPortrait:true)
  let result: [DetailPosterQuality] = await DetailPosterSelection.collect(sources:["a","b","c","d","e","f"],budget:0.25,discover:{ timeout in
    assert(timeout <= 4)
    // Discover only after initial low-quality jobs really completed, rather
    // than assuming a loaded CI host wakes 10ms/50ms sleeps in that order.
    await probe.waitForInitialCompletions(); return ["tenhow"]
  }) { source, timeout in
    assert(timeout > 0 && timeout <= 5)
    await probe.start(); await Task.yield(); await probe.end()
    return source == "tenhow" ? high : low
  }
  assert(result.count == 6 && DetailPosterQuality.winner(result)?.source == "tenhow", "sources=\(result.map(\.source))")
  assert(result.first?.source == "old", "Original low-quality completion precedes discovered winner")
  let stats=await probe.snapshot(); assert(stats.0 == 0 && stats.1 <= 2 && stats.2 == 6)
  var presentation=DetailPosterPresentation<Int>(key:"k",generation:UUID(),layout:.resolving)
  let generation=presentation.generation
  presentation.complete(1,key:"k",generation:generation); presentation.complete(2,key:"k",generation:generation)
  assert(presentation.layout.artwork == 1)
  let missed: [String] = await DetailPosterSelection.collect(sources:["a","b","c","d","e","f"],budget:0.2,discover:{ _ in [] }) { source,_ in source }
  assert(Set(missed) == Set(["a","b","c","d","e","f"]))
  let empty: [String] = await DetailPosterSelection.collect(sources:[],budget:0.2,discover:{ _ in ["tenhow"] }) { source,_ in source }
  assert(empty == ["tenhow"])
  let start=ProcessInfo.processInfo.systemUptime
  let timed: [String] = await DetailPosterSelection.collect(sources:["old"],budget:0.04,discover:{ _ in
    do { try await Task.sleep(nanoseconds:1_000_000_000); return ["tenhow"] } catch { return [] }
  }) { source,_ in source }
  assert(timed == ["old"] && ProcessInfo.processInfo.systemUptime-start < 0.3)
  let cancelled=Task { await DetailPosterSelection.collect(sources:["old"],budget:1,discover:{ _ in
    do { try await Task.sleep(nanoseconds:1_000_000_000); return ["tenhow"] } catch { return [] }
  }) { source,_ in source } }
  try? await Task.sleep(nanoseconds:10_000_000); cancelled.cancel()
  let cancelledValues=await cancelled.value; assert(cancelledValues.isEmpty)
  for (asin, expected) in [("B09HS8HBR7", "https://m.media-amazon.com/images/I/91ktf3uskCL.jpg"), ("B0B92LKJT8", "https://m.media-amazon.com/images/I/81N2rlJarrL.jpg")] {
    let html=try String(contentsOf:fixtures.appendingPathComponent("amazon-"+asin+".html"),encoding:.utf8)
    assert(try AmazonPoster.images(html:html,asin:asin) == [expected])
    assert(try AmazonPoster.images(html:html,asin:"B000000000").isEmpty)
    assert(try AmazonPoster.images(html:html+"validateCaptcha",asin:asin).isEmpty)
  }
  let amazon="<link rel='canonical' href='https://www.amazon.co.jp/dp/B09HS8HBR7'><input id='ASIN' value='B09HS8HBR7'><img id='landingImage' data-old-hires='https://m.media-amazon.com/images/I/main.jpg'><img data-old-hires='https://m.media-amazon.com/images/I/recommended.jpg'>"
  assert(try AmazonPoster.images(html:amazon,asin:"B09HS8HBR7") == ["https://m.media-amazon.com/images/I/main.jpg"])
  assert(try AmazonPoster.images(html:amazon.replacingOccurrences(of:"/dp/B09HS8HBR7",with:"/dp/B000000000"),asin:"B09HS8HBR7").isEmpty)
  for bad in ["https://www.amazon.co.jp/ap/signin", "https://www.amazon.co.jp/dp/B000000000", "https://www.amazon.co.jp.evil.test/dp/B09HS8HBR7", "https://www.amazon.co.jp/dp/B09HS8HBR7?x=1"] { assert(!AmazonPoster.allowedPage(URL(string:bad)!,asin:"B09HS8HBR7")) }
  for bad in ["https://m.media-amazon.com.evil.test/images/I/x.jpg", "https://m.media-amazon.com/images/I/x.jpg?q=1", "http://m.media-amazon.com/images/I/x.jpg", "https://m.media-amazon.com/other/x.jpg"] { assert(!AmazonPoster.allowedImage(URL(string:bad)!)) }
  let media = "https://m.media-amazon.com/images/I/91ktf3uskCL"
  for suffix in ["._AC_SL1500_", "._SL2560_"] {
    assert(AmazonPoster.originalImage(URL(string:media+suffix+".jpg")!)?.absoluteString == media+".jpg")
  }
  for suffix in ["._AC_SX500_", "._SL0_", "._SL99999_", "._AC_SL1500_CR0,0,1,1_"] {
    let url=URL(string:media+suffix+".jpg")!
    assert(AmazonPoster.originalImage(url) == (AmazonPoster.allowedImage(url) ? url : nil))
  }
  assert(AmazonPoster.originalImage(URL(string:media+"._SL1500_.jpg?token=x")!) == nil)
  assert(AmazonPoster.originalImage(URL(string:media.replacingOccurrences(of:"m.media-amazon.com",with:"evil.test")+".jpg")!) == nil)
  // Build 273: exact-ASIN MAIN._SCRM_ CDN (no HTML). Fixture ASINs match Build196 originals.
  assert(AmazonPoster.directHQ(asin:"B09HS8HBR7") == "https://m.media-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg")
  assert(AmazonPoster.directHQ(asin:"B0B92LKJT8") == "https://m.media-amazon.com/images/P/B0B92LKJT8.01.MAIN._SCRM_.jpg")
  assert(AmazonPoster.directHQ(asin:"bad") == nil)
  assert(AmazonPoster.directHQ(asin:"B09HS8HBR7!") == nil)
  assert(AmazonPoster.allowedImage(URL(string:"https://m.media-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg")!))
  assert(AmazonPoster.allowedImage(URL(string:"https://m.media-amazon.com/images/P/B09HS8HBR7.09.MAIN._SCRM_.jpg")!))
  assert(AmazonPoster.originalImage(URL(string:"https://m.media-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg")!)?.absoluteString == "https://m.media-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg")
  for bad in ["https://m.media-amazon.com/images/P/B09HS8HBR7.09._SL1500_.jpg", "https://m.media-amazon.com/images/P/B09HS8HBR7.09.LZZZZZZZ.jpg", "https://m.media-amazon.com/images/P/B09HS8HBR7.02.MAIN._SCRM_.jpg", "https://ec2.images-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg", "https://m.media-amazon.com/images/P/B09HS8HBR7.01.MAIN._SCRM_.jpg?x=1"] {
    assert(!AmazonPoster.allowedImage(URL(string:bad)!))
  }
  let native=DetailPosterQuality(source:"native2530",width:1778,height:2530,originalPortrait:true)
  let capped=DetailPosterQuality(source:"native1800",width:1260,height:1800,originalPortrait:true)
  assert(native.score > capped.score && DetailPosterQuality.winner([capped,native])?.source == native.source)
  let both: [String] = await DetailPosterSelection.collect(sources:["a","b","c","d","e","f"],budget:0.2,discover:{ _ in ["tenhow","amazon"] }) { source,_ in source }
  assert(both.count == 6 && both.contains("tenhow") && both.contains("amazon") && !both.contains("e") && !both.contains("f"))
  print("PASS production Tenhow: 9 live-record fixtures, 1740 explicit actor paths, exact CID/ASIN, adversarial records, aliases, HTTPS/redirects, late high-resolution winner, six images/two jobs, shared budget/cancellation, one publication; Amazon exact ASIN MAIN._SCRM_ directHQ + HTML fixture path, two reserved opportunities")
 }
}
'''
tests=tests.replace('assert(try ', 'try verify(try ')
tests='func verify(_ value: @autoclosure () throws -> Bool) throws { let ok = try value(); assert(ok) }\n'+tests
if not shutil.which('swiftc'):
    print('PASS Tenhow integration static checks; production Swift fixture tests require macOS CI')
else:
    with tempfile.TemporaryDirectory() as td:
        p=Path(td); (p/'main.swift').write_text(core+'\n'+tests)
        subprocess.run(['swiftc','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test'),str(root/'scripts/tenhow-fixtures')],check=True,timeout=60)
