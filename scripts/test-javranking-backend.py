"""Execute shipping Swift backend models, URL policy and URLSession transport on macOS.
Only the transport response and unrelated native movie dependency are substituted.
"""
from pathlib import Path
import json,shutil,subprocess,tempfile
R=Path(__file__).resolve().parents[1]
F=R/'scripts/javranking-fixtures/backend-v1'
core=(R/'AVDB/Services/JavRankingCore.swift').read_text()
source=(R/'AVDB/Services/JavRankingSource.swift').read_text()
view=(R/'AVDB/Views/JavRankingView.swift').read_text()
for f in F.glob('*.json'):
 d=json.loads(f.read_text());assert d['schemaVersion']==1
 assert not any(k in f.read_text() for k in ['"coverURL"','"thumbURL"','"cookie"','"nativeID"'])
assert 'JRBackendFilmCell(item: item)' in view and '.avdbCatalogAccountChanged' in view
assert 'MoviePosterCard(movie: movie)' in view
assert 'rejectRedirects: true' in source and 'javranking.backendHTTPS' in source
if not shutil.which('swiftc'):
 print('PASS fixture/static contracts; SKIP native Swift backend runtime (macOS required)');raise SystemExit(0)
transport=source.split('@MainActor final class JavRankingSource:')[0]
backend='@MainActor final class JRBackendClient:'+source.split('@MainActor final class JRBackendClient:')[1]
stubs=r'''
@MainActor final class JavRankingSource { static let shared = JavRankingSource(); func cancelMappings() {} }
final class Mock: URLProtocol, @unchecked Sendable {
 static var body = Data(); static var status = 200; static var delay = 0.01
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 var work: DispatchWorkItem?
 override func startLoading() {
  precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
  precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
  let body = Self.body, status = Self.status
  let work = DispatchWorkItem { [self] in
   let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"] )!
   client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
   client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
  }; self.work = work; DispatchQueue.global().asyncAfter(deadline:.now()+Self.delay,execute:work)
 }
 override func stopLoading() { work?.cancel() }
}
func check(_ ok: Bool, _ name: String) { precondition(ok,name); print("PASS "+name) }
@main struct Regression {
 @MainActor static func main() async throws {
  let path = CommandLine.arguments[1]
  for name in ["home","topics","explore","filter","search"] {
   let data = try Data(contentsOf:URL(fileURLWithPath:path+"/snapshot-"+name+".json"))
   let envelope = try JRBackendEnvelope.decode(data)
   check(envelope.data != nil, "actual sanitized "+name+" envelope decoding")
   if name == "home" {
    let sections = envelope.data!.sections!
    check(sections.map(\.id) == ["pick","random","rankings","weekly","monthly","awarded","actors"],"seven sections exact order")
    check(sections.last!.actors!.count == 3,"actor groups retained")
    let source = sections.flatMap { $0.items ?? [] }
    check(source.map(\.rank) == source.map { $0.video.rank },"all source ranks preserved")
    var duplicateRoot = try JSONSerialization.jsonObject(with:data) as! [String:Any]
    var duplicatePayload = duplicateRoot["data"] as! [String:Any]
    var duplicateSections = duplicatePayload["sections"] as! [[String:Any]]
    let original = (duplicateSections[1]["items"] as! [[String:Any]])[0]
    duplicateSections[3]["items"] = [original, original]
    duplicatePayload["sections"] = duplicateSections; duplicateRoot["data"] = duplicatePayload
    let duplicate = try JRBackendEnvelope.decode(JSONSerialization.data(withJSONObject:duplicateRoot)).data!.sections![3].items!
    check(duplicate.count == 2 && duplicate[0].sourcePath == duplicate[1].sourcePath && duplicate[0].rank == duplicate[1].rank,"fixture duplicate identity/rank is not deduplicated")
    check(source.allSatisfy { $0.video.image == nil && $0.video.title == "等待原生番号核验" },"no source media or invented native metadata")
   }
  }
  for invalid in ["http://example.com","https://u:p@example.com","https://example.com:8000","https://example.com/solver","https://example.com?url=x","https://127.0.0.1","https://localhost","https://example.com/#x"] {
   do { _ = try JRBackendPolicy.endpoint(invalid); fatalError("accepted "+invalid) } catch {}
  }
  check(try JRBackendPolicy.endpoint("") == nil,"empty is disabled, not dead loopback")
  let ip = try JRBackendPolicy.endpoint("https://163.47.40.207")!
  check(ip.absoluteString == "https://163.47.40.207/api/v1/javranking","IP TLS configurable without domain")
  for route in ["solver","../home","https://evil.test"] {
   do { _ = try JRBackendPolicy.request(base:ip,route:route); fatalError("accepted route") } catch {}
  }
  do { _ = try JRBackendPolicy.request(base:ip,route:"page",query:[.init(name:"path",value:"https://evil.test")]);fatalError("proxy") } catch {}
  for denied in ["/zh-hans/videos/1/", "/zh-hans/actors/a/?page=6", "/zh-hans/actors/a/?url=x", "//evil.test/zh-hans/", "/zh-hans/actors/a/%2e%2e/"] {
   do { _ = try JRBackendPolicy.request(base:ip,route:"page",query:[.init(name:"path",value:denied)]);fatalError("denied source") } catch {}
  }
  let next = try JRBackendPolicy.request(base:ip,route:"page",query:[.init(name:"path",value:"/zh-hans/rankings/dmm-weekly/?page=2")])
  check(next.host == ip.host && next.path == JRBackendPolicy.prefix+"/page","source next-page stays fixed API host/path")
  check(JRPolicy.exactCode("R18-292") != JRPolicy.exactCode("R1-8292"),"numeric prefix not stripped")
  check(JRPolicy.exactCode("FC2-PPV-12345") == JRPolicy.exactCode("FC2-12345"),"explicit FC2 equivalence")
  let defaults = UserDefaults(suiteName:"backend-"+UUID().uuidString)!
  let client = JRBackendClient(defaults:defaults,protocolClasses:[Mock.self])
  do { _ = try await client.fetch("home");fatalError("unconfigured") } catch {}
  try client.configure("https://example.com",defaults:defaults)
  Mock.body = try Data(contentsOf:URL(fileURLWithPath:path+"/snapshot-home.json"))
  check(try await client.fetch("home").data?.sections?.count == 7,"shipping transport decodes home")
  var root = try JSONSerialization.jsonObject(with:Mock.body) as! [String:Any]
  root["stale"] = true; root["status"] = "upstream_error"
  Mock.body = try JSONSerialization.data(withJSONObject:root)
  let stale = try await client.fetch("home")
  check(stale.stale && stale.data != nil && stale.notice.contains("旧缓存"),"stale error keeps last success")
  root["data"] = NSNull();root["fetchedAt"] = NSNull();root["status"] = "pending"
  Mock.body = try JSONSerialization.data(withJSONObject:root);Mock.status = 202
  check(try await client.fetch("home").data == nil,"202 is pending not an empty successful list")
  Mock.status = 503
  do { _ = try await client.fetch("home");fatalError("503") } catch { check(error.localizedDescription.contains("503"),"HTTP error surfaced") }
  Mock.status = 200;Mock.delay = 0.5
  let flight = Task { try await client.fetch("home") }
  try await Task.sleep(nanoseconds:10_000_000);flight.cancel()
  do { _ = try await flight.value;fatalError("cancelled published") } catch { print("PASS cancelled transport cannot publish") }
  let old = Task { try await client.fetch("home") }
  try await Task.sleep(nanoseconds:10_000_000)
  try client.configure("https://other.example",defaults:defaults)
  do { _ = try await old.value;fatalError("old endpoint published") } catch { print("PASS endpoint generation isolation") }
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'Backend.swift';p.write_text(core+'\n'+transport+'\n'+backend+'\n'+stubs)
 exe=Path(tmp)/'backend'
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(exe)],check=True)
 subprocess.run([str(exe),str(F)],check=True,timeout=60)
