"""Production Swift parser/client regression and controlled (not device) timing.
Actual public HTML captured 2026-10-12. No live JavDB/account writes.
"""
from pathlib import Path
import gzip, shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
if not shutil.which('swiftc'):
    print('SKIP production Swift timing/client tests: requires macOS Swift/Combine')
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as td:
    d=Path(td)
    fixtures=root/'scripts/javranking-fixtures'
    for p in fixtures.glob('*.html.gz'):
        (d/p.stem).write_bytes(gzip.decompress(p.read_bytes()))
    bench=r'''
import Foundation
@main struct Benchmark {
 static func main() throws {
  setbuf(stdout, nil)
  let base=URL(string:"https://javranking.cc")!
  for path in CommandLine.arguments.dropFirst() {
   if path.hasSuffix(".json") {
    let data = try Data(contentsOf: URL(fileURLWithPath: path)); let start = Date()
    let index = try JRIndex.parse(data, base: base)
    print("INDEX file=\(URL(fileURLWithPath: path).lastPathComponent) decoded=\(data.count) seconds=\(Date().timeIntervalSince(start)) videos=\(index.videos.count)")
    continue
   }
   let html=try String(contentsOfFile:path, encoding:.utf8)
   let route=path.contains("javlibrary") ? "/zh-hans/rankings/javlibrary-top250/" : path.contains("most-awarded") ? "/zh-hans/most-awarded-videos/" : path.contains("detail") ? "/zh-hans/videos/26/" : "/zh-hans/"
   let start=Date()
   let page=try JRHTML.parse(html,path:route,base:base)
   print("PARSER file=\(URL(fileURLWithPath:path).lastPathComponent) decoded=\(html.utf8.count) seconds=\(Date().timeIntervalSince(start)) videos=\(page.videos.count) links=\(page.links.count) metadata=\(page.metadata.count) comments=\(page.paragraphs.count)")
   if CommandLine.arguments[0].contains("after"), route.contains("javlibrary") {
    precondition(page.videos.count == 250)
    precondition(page.videos.first?.code == "START-257")
    precondition(page.videos[4].code == "IPX-811")
    precondition(page.videos.first?.rank == 1 && page.videos.last?.rank == 250)
    precondition(!page.links.contains { $0.path.contains("/videos/") })
   }
  }
 }
}
'''
    current=(root/'AVDB/Services/JavRankingCore.swift').read_text()
    baseline=subprocess.check_output(['git','show','c2eaf4b:AVDB/Services/JavRankingCore.swift'],cwd=root,text=True)
    args=[str(fixtures/'index.html'),str(fixtures/'videos-detail.html'),str(fixtures/'rankings.html'),str(d/'javlibrary-top250.html'),str(d/'most-awarded-videos.html'),str(fixtures/'filter-index.json'),str(fixtures/'search-index.json')]
    for label,core in [('before',baseline),('after',current)]:
        timed = bench
        if label == 'after':
            timed = timed.replace('   let start=Date()\n   let page=', r'''   let previewStart=Date()
   if let preview=try JRHTML.firstCards(html,path:route,base:base) {
    print("FIRST_CARDS file=\(URL(fileURLWithPath:path).lastPathComponent) seconds=\(Date().timeIntervalSince(previewStart)) videos=\(preview.videos.count)")
    precondition(preview.videos.count > 0 && preview.videos.count <= 13)
   }
   let start=Date()
   let page=''')
        p=d/(label+'.swift');p.write_text(core+'\n'+timed.replace('    precondition(page.videos.first?.rank == 1 && page.videos.last?.rank == 250)', '' if label == 'before' else '    precondition(page.videos.first?.rank == 1 && page.videos.last?.rank == 250)'))
        subprocess.run(['swiftc','-O','-swift-version','5','-parse-as-library',str(p),'-o',str(d/label)],check=True)
        print('CONTROLLED PRODUCTION PARSER',label,flush=True)
        subprocess.run([str(d/label)]+args,check=True,timeout=180)
    main=r'''
import Foundation
import Combine
struct Movie: Hashable { let id: String; let number: String?; var title: String? { nil } }
@MainActor final class JavDBSDK {
 static let shared=JavDBSDK()
 var calls: [String:Int]=[:]; var active=0; var maximum=0
 func search(keyword:String,page:Int = 1,type:String = "movie") async throws -> [Movie] {
  calls[keyword,default:0] += 1; active += 1; maximum=max(active,maximum)
  defer { active -= 1 }
  try await Task.sleep(nanoseconds: keyword.hasPrefix("SLOW-") ? 400_000_000 : 40_000_000)
  precondition(type == "movie")
  if keyword == "MISS-001" { return [] }
  if keyword == "EMPTY-001" { return [Movie(id:"",number:keyword)] }
  if keyword == "WRONG-001" { return [Movie(id:"wrong",number:"OTHER-001")] }
  if keyword == "FAIL-001" { throw JRError.message("mock lookup unavailable") }
  if keyword == "FC2-PPV-12345" { return [Movie(id:"fc2",number:"FC2PPV12345")] }
  if keyword == "AMB-001" { return [Movie(id:"a",number:keyword),Movie(id:"b",number:keyword)] }
  if keyword == "IPX-811" { return [Movie(id:"bad",number:"IPX-8110"),Movie(id:"right",number:"IPX811")] }
  return [Movie(id:keyword,number:keyword)]
 }
}
final class Mock: URLProtocol, @unchecked Sendable {
 static let lock=NSLock(); static var counts:[String:Int]=[:]; static var bodies:[String:Data]=[:]
 override class func canInit(with request:URLRequest)->Bool { true }
 override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
 override func startLoading() {
  let path=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.path
  Self.lock.lock(); Self.counts[path,default:0] += 1
  let body=Self.bodies[path] ?? Data("<main><h1>Mock</h1></main>".utf8); Self.lock.unlock()
  DispatchQueue.global().asyncAfter(deadline:.now()+0.02) { [self] in
   let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Length":String(body.count)])!
   client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
   for offset in stride(from:0,to:body.count,by:65536) {
    client?.urlProtocol(self,didLoad:body.subdata(in:offset..<min(offset+65536,body.count)))
   }
   client?.urlProtocolDidFinishLoading(self)
  }
 }
 override func stopLoading() {}
}
func check(_ condition: @autoclosure () -> Bool, line: Int = #line) {
 if !condition() { fputs("FAIL production client line=\(line)\n", stderr); exit(1) }
}
@main struct ClientTest {
 @MainActor static func main() async throws {
  setbuf(stdout, nil)
  print("CLIENT begin")
  let dir=CommandLine.arguments[1]
  let large=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
  Mock.bodies["/zh-hans/filter-index.json"]=try Data(contentsOf:URL(fileURLWithPath:dir+"/filter-index.json"))
  Mock.bodies["/zh-hans/explore/"]=try Data(contentsOf:URL(fileURLWithPath:dir+"/explore.html"))
  Mock.bodies["/transfer/"]=large
  Mock.bodies["/zh-hans/most-awarded-videos/"]=large
  let defaults=UserDefaults(suiteName:"jr-test-\(UUID())")!
  let source=JavRankingSource(defaults:defaults,protocolClasses:[Mock.self])
  async let a=source.page("/zh-hans/explore/"); async let b=source.page("/zh-hans/explore/")
  let pages=try await (a,b)
  precondition(!pages.0.videos.isEmpty && pages.0.videos == pages.1.videos)
  precondition(Mock.counts["/zh-hans/explore/"] == 1 && Mock.counts["/zh-hans/filter-index.json"] == nil)
  _=try await source.page("/zh-hans/explore/?page=2")
  _=try await source.page("/zh-hans/explore/?page=3")
  precondition(Mock.counts["/zh-hans/filter-index.json"] == 1)
  var previewCount=0
  let subscription=source.$previews.sink { previews in
   if let preview=previews["/zh-hans/most-awarded-videos/"] { previewCount=preview.videos.count }
  }
  let complete=try await source.page("/zh-hans/most-awarded-videos/")
  precondition(previewCount > 0 && previewCount <= 13 && complete.videos.count == 2685)
  subscription.cancel()
  async let x=source.matchedMovie(code:"IPX-811"); async let y=source.matchedMovie(code:"IPX-811")
  let pair=try await (x,y); precondition(pair.0?.id == "right" && pair.1?.id == "right")
  precondition(JavDBSDK.shared.calls["IPX-811"] == 1)
  let miss=try await source.matchedMovie(code:"MISS-001")
  precondition(miss == nil)
  do { _=try await source.matchedMovie(code:"AMB-001"); preconditionFailure("ambiguity hidden") } catch {}
  precondition(JRPolicy.exactCode("IPX-811") != JRPolicy.exactCode("IPX-8110"))
  precondition(JRPolicy.exactCode("FC2-PPV-12345") == JRPolicy.exactCode("FC2PPV12345"))
  precondition(JRPolicy.exactCode("FC2-12345") == nil)
  await withTaskGroup(of:Void.self) { group in
   for n in 100..<112 { group.addTask { _=try? await source.matchedMovie(code:"TEST-\(n)") } }
  }
  precondition(JavDBSDK.shared.maximum <= 3)
  precondition(JavDBSDK.shared.calls.count == 15)
  let slowA = Task { try await source.matchedMovie(code:"SLOW-001") }
  let slowB = Task { try await source.matchedMovie(code:"SLOW-002") }
  let slowC = Task { try await source.matchedMovie(code:"SLOW-003") }
  try await Task.sleep(nanoseconds:10_000_000)
  let tapStart = Date()
  let tapped = try await source.matchedMovie(code:"TAP-001", interactive:true)
  precondition(tapped?.id == "TAP-001" && Date().timeIntervalSince(tapStart) < 0.25)
  precondition(JavDBSDK.shared.maximum == 4)
  _ = try await (slowA.value, slowB.value, slowC.value)
  let cached = try await source.matchedMovie(code:"TAP-001", interactive:true)
  precondition(cached?.id == "TAP-001" && JavDBSDK.shared.calls["TAP-001"] == 1)
  APIClient.shared.token = "synthetic-new-account"
  _ = try await source.matchedMovie(code:"TAP-001", interactive:true)
  precondition(JavDBSDK.shared.calls["TAP-001"] == 2)
  let empty=try await source.matchedMovie(code:"EMPTY-001")
  let wrong=try await source.matchedMovie(code:"WRONG-001")
  let fc2=try await source.matchedMovie(code:"FC2-PPV-12345")
  precondition(empty == nil && wrong == nil && fc2?.id == "fc2")
  do { _=try await source.matchedMovie(code:"FAIL-001"); preconditionFailure("error hidden") } catch {}
  _=try await source.matchedMovie(code:"IPX-811",refresh:true)
  precondition(JavDBSDK.shared.calls["IPX-811"] == 2)
  precondition(JRPolicy.catalogueCode("IPX247 title") == "IPX247")
  precondition(JRPolicy.catalogueCode("unrelated IPX-247 title") == nil)
  let old=Task { try await source.page("/zh-hans/help/") }
  try await Task.sleep(nanoseconds:1_000_000)
  try source.configure("https://example.org",defaults:defaults)
  do { _=try await old.value; preconditionFailure("old generation published") } catch {}
  precondition(source.cachedPage("/zh-hans/explore/") == nil)
  let cancelled=Task { try await source.matchedMovie(code:"STOP-001") }
  try await Task.sleep(nanoseconds:1_000_000); source.cancelMappings()
  do { _=try await cancelled.value; preconditionFailure("cancelled mapping published") } catch {}
  let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[Mock.self]
  let legacy=URLSession(configuration:config)
  let url=URL(string:"https://javranking.cc/transfer/")!
  var start=Date(); let (bytes,_)=try await legacy.bytes(from:url); var result=Data()
  for try await byte in bytes { result.append(byte) }
  let before=Date().timeIntervalSince(start)
  let delegate=JRRedirectPolicy(base:URL(string:"https://javranking.cc")!)
  let modern=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
  start=Date(); let chunks=try await delegate.download(URLRequest(url:url),session:modern)
  let after=Date().timeIntervalSince(start)
  print("TRANSFER CHECK legacy=\(result.count) chunks=\(chunks.count) fixture=\(large.count)")
  precondition(result == chunks && chunks == large)
  print("CONTROLLED TRANSFER decoded=\(large.count) legacyMainActorByteSeconds=\(before) backgroundChunkSeconds=\(after) (URLProtocol replay, not device/network)")
  legacy.invalidateAndCancel(); modern.invalidateAndCancel()
  print("PASS production singleflight/lazy index/exact mapping/ambiguity/concurrency3/domain cancellation/leaving cancellation")
 }
}
'''
    # Exercise the shipping resolver, not a mock that repeats its matching policy.
    sdk = (root/'AVDB/Services/JavDBSDK.swift').read_text()
    helper = '    public func exactMovie' + sdk.split('    public func exactMovie', 1)[1].split('    /// 分类搜索：', 1)[0]
    main = main.replace('final class Mock: URLProtocol', 'extension JavDBSDK {\n' + helper + '\n}\nfinal class Mock: URLProtocol')
    cache = sdk.split('    // Memory only,', 1)[1].split('    // MARK: - 搜索类', 1)[0]
    main = main.replace('@MainActor final class JavDBSDK {', '@MainActor final class APIClient { static let shared = APIClient(); var token: String? }\n@MainActor final class JavDBSDK {\n private let client = APIClient.shared\n // Memory only,' + cache)
    p=d/'client.swift';p.write_text(current+'\n'+(root/'AVDB/Services/JavRankingSource.swift').read_text()+'\n'+main.replace('precondition(', 'check('))
    subprocess.run(['swiftc','-O','-swift-version','5','-parse-as-library',str(p),'-o',str(d/'client')],check=True)
    subprocess.run([str(d/'client'),str(fixtures),str(d/'most-awarded-videos.html')],check=True,timeout=180)
