"""Synthetic replay of shipping JAVLibrary API/parser + shared metadata queue.
Never logs in, reads a live token or writes to VPS/115. Run Swift on macOS CI.
"""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
read = lambda name: (root / name).read_text()
source = read('AVDB/Services/JAVLibrarySource.swift')
view = read('AVDB/Views/JAVLibraryRankingView.swift')
client = read('AVDB/Services/ExternalLibraryClient.swift')
assert '/api/v1/javlibrary/rankings' in client
assert 'JAVLibraryRankingView()' in read('AVDB/Views/Rankings/RankingsView.swift')
assert 'enrichMissAV: false' in view and 'snapshot.items.prefix(visibleCount)' in view
assert 'ranks: Dictionary(uniqueKeysWithValues:' in view
assert 'MovieDetailView(movieID: movie.id)' in read('AVDB/Views/MissAVRankingView.swift')
assert 'WKWebView' not in source + view and 'Pan115Client' not in source + view
assert 'local_tid' not in source.replace('// poster/avatar/local_tid deliberately never become an AVDB identity/cover.', '')
for name in ['JAVLibrarySource.swift','JAVLibraryRankingView.swift']:
    assert read('AVDB.xcodeproj/project.pbxproj').count(f'/* {name} in Sources */') == 2
print('PASS JAVLibrary native wiring, separate queue instances, original ranks, no web view/write APIs')
if not shutil.which('swiftc'):
    print('SKIP Swift runtime locally; required macOS CI replay');raise SystemExit(0)
stubs = r'''
struct Movie { let id: String }
struct Actor { let id: String; var name: String?; var nameZht: String?; var otherName: String? }
@MainActor final class APIClient { static let shared = APIClient(); var token: String? = "synthetic-account" }
@MainActor final class MissAVSource {
 static let shared = MissAVSource(); var generation = 0; var calls = 0
 struct Detail { let video: JRVideo }
 func detail(_ v: JRVideo) async throws -> Detail { calls += 1; return Detail(video:v) }
 func actressAliases(_ a: MissAVActress) async throws -> [String] { calls += 1; return [] }
}
@MainActor final class JavDBSDK {
 static let shared = JavDBSDK(); var actors: [Actor] = []; var codes: [String] = []
 func exactMovie(code: String, verifyAllPages: Bool) async throws -> Movie? { codes.append(code); return Movie(id:"native-id") }
 func searchActors(keyword: String, page: Int) async throws -> [Actor] { actors }
}
final class Tokens: ExternalTokenStore {
 var value: String? = "synthetic-key"
 func read() throws -> String? { value }
 func write(_ s: String) throws { value=s }
 func clear() throws { value=nil }
}
final class Replay: URLProtocol, @unchecked Sendable {
 static var status=200; static var payload=Data(); static var sent: [URLRequest]=[]
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.sent.append(request)
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Self.payload);client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
func fixture(kind: String="mostwanted", ranks: [Int]=[3,8,27]) throws -> Data {
 let actor = kind == "actors"
 let items: [[String:Any]] = ranks.map { rank in
  var item: [String:Any] = ["rank":rank,"entity_type":actor ? "actor":"movie","source_url":"https://www.javlibrary.com/cn/item-\(rank)","local_tid":999,"poster":"https://not-avdb.invalid/p.jpg"]
  if actor { item["name"]="Synthetic";item["aliases"]=["Alias"] }
  else { item["number"]="IPX-247";item["title"]="Source title" }
  return item
 }
 return try JSONSerialization.data(withJSONObject:["code":0,"data":["source":"javlibrary","kind":kind,"entity_type":actor ? "actor":"movie","fetched_at":"2026-10-14T13:32:00+00:00","source_url":"https://www.javlibrary.com/cn/","pages":5,"count":items.count,"stale":true,"last_attempt":["ok":0,"attempted_at":"2026-10-14T16:00:00+00:00","error":"untrusted server error"],"items":items]])
}
@main struct Tests {
 @MainActor static func wait(_ q: MissAVMetadata, _ r: MissAVMetadata.Request) async throws {
  for _ in 0..<200 { if !q.value(r).loading { return };try await Task.sleep(nanoseconds:10_000_000) }
  fatalError("queue timeout")
 }
 @MainActor static func main() async throws {
  let bytes=try fixture()
  let snapshot=try JAVLibrarySnapshot.decode(bytes,kind:.mostwanted)
  precondition(snapshot.items.map(\.rank)==[3,8,27] && snapshot.stale && snapshot.lastAttempt?.ok==0)
  precondition(Array(snapshot.items.prefix(2)).map(\.rank)+Array(snapshot.items.dropFirst(2)).map(\.rank)==[3,8,27])
  precondition(snapshot.items[0].video.image==nil && snapshot.items[0].video.code=="IPX-247")
  for bad in [try fixture(ranks:[8,3]), try fixture(ranks:[3,3]), Data("{}".utf8)] {
   do { _ = try JAVLibrarySnapshot.decode(bad,kind:.mostwanted);fatalError("bad schema accepted") } catch ExternalLibraryError.schema {}
  }
  do { _ = try JAVLibrarySnapshot.decode(bytes,kind:.bestrated);fatalError("kind mixed") } catch ExternalLibraryError.schema {}
  _ = try JAVLibrarySnapshot.decode(fixture(kind:"bestrated"),kind:.bestrated)
  let actors=try JAVLibrarySnapshot.decode(fixture(kind:"actors"),kind:.actors)
  precondition(actors.items[0].actor.aliases==["Synthetic","Alias"])
  precondition(JRPolicy.exactCode("IPX-247") == JRPolicy.exactCode("ipx247"))
  precondition(JRPolicy.exactCode("IPX-247-extra") == nil)
  precondition(MissAVIdentity.exact(["Alias"],["Name、ＡＬＩＡＳ"]))
  precondition(!MissAVIdentity.exact(["Syn"],["Synthetic"]))
  let suite="javlibrary-regression-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!;defer { defaults.removePersistentDomain(forName:suite) }
  let tokens=Tokens();let settings=ExternalLibrarySettings(store:tokens,defaults:defaults)
  let client=ExternalLibraryClient { let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[Replay.self];return c }
  defer { client.cancelRequests() }
  do { _ = try await client.javlibrary(.mostwanted,settings:settings);fatalError("disabled used network") } catch ExternalLibraryError.rankingNotConfigured {}
  precondition(Replay.sent.isEmpty)
  try settings.save(baseURL:"https://fixture.invalid",enabled:true,replacementToken:"synthetic-key")
  Replay.payload=bytes
  let page=try await client.javlibrary(.mostwanted,settings:settings)
  precondition(page.items.map(\.rank)==[3,8,27])
  let sent=Replay.sent.last!
  precondition(sent.url!.path=="/api/v1/javlibrary/rankings" && sent.url!.query=="kind=mostwanted")
  precondition(sent.value(forHTTPHeaderField:"X-API-Key")=="synthetic-key" && sent.value(forHTTPHeaderField:"Cookie")==nil)
  Replay.status=401
  do { _ = try await client.javlibrary(.actors,settings:settings);fatalError("401 accepted") } catch ExternalLibraryError.http(401) {}
  Replay.status=200;Replay.payload=Data("{}".utf8)
  do { _ = try await client.javlibrary(.actors,settings:settings);fatalError("invalid response accepted") } catch ExternalLibraryError.schema {}
  var generation=0
  let q=MissAVMetadata(sourceName:"JAVLibrary",generation:{generation},enrichMissAV:false)
  let movie=MissAVMetadata.Request.movie(snapshot.items[0].video)
  q.enqueue(movie);try await wait(q,movie)
  precondition(q.value(movie).movie?.id=="native-id" && JavDBSDK.shared.codes==["IPX-247"])
  precondition(MissAVSource.shared.calls==0)
  let actor=MissAVMetadata.Request.actor(actors.items[0].actor)
  JavDBSDK.shared.actors=[Actor(id:"one",name:"Synthetic",nameZht:nil,otherName:nil)]
  q.enqueue(actor);try await wait(q,actor);precondition(q.value(actor).actor?.id=="one")
  JavDBSDK.shared.actors.append(Actor(id:"two",name:"Other",nameZht:nil,otherName:"Alias"))
  q.enqueue(actor,retry:true);try await wait(q,actor)
  precondition(q.value(actor).actor==nil && q.value(actor).candidates.count==2)
  JavDBSDK.shared.actors=[Actor(id:"fuzzy",name:"Synthetic extra",nameZht:nil,otherName:nil)]
  q.enqueue(actor,retry:true);try await wait(q,actor)
  precondition(q.value(actor).actor==nil && !q.value(actor).candidates.isEmpty)
  precondition(MissAVSource.shared.calls==0)
  var calls=0,active=0,maximum=0
  let bounded=MissAVMetadata(sourceName:"JAVLibrary",generation:{generation},enrichMissAV:false,resolver:{ r in
   calls+=1;active+=1;maximum=max(maximum,active);defer { active-=1 }
   try await Task.sleep(nanoseconds:30_000_000)
   return MissAVMetadata.Result(movie:Movie(id:r.key),loading:false)
  })
  let requests=(1...6).map { MissAVMetadata.Request.movie(JRVideo(path:"/\($0)",code:"TEST-\($0)",title:"",image:nil,subtitle:"")) }
  for r in requests { bounded.enqueue(r);bounded.enqueue(r) }
  for r in requests { try await wait(bounded,r) }
  precondition(calls==6 && maximum==2)
  precondition(requests.map { bounded.value($0).movie!.id }==requests.map(\.key))
  bounded.reset();bounded.enqueue(requests[0]);generation+=1;bounded.enqueue(requests[1]);try await wait(bounded,requests[1])
  precondition(bounded.value(requests[0]).movie==nil)
  bounded.reset();bounded.enqueue(requests[2]);APIClient.shared.token="new-synthetic-account";bounded.enqueue(requests[3]);try await wait(bounded,requests[3])
  precondition(bounded.value(requests[2]).movie==nil)
  bounded.reset();bounded.enqueue(requests[4]);bounded.suspend();try await Task.sleep(nanoseconds:60_000_000)
  precondition(bounded.results.isEmpty)
  bounded.enqueue(requests[4]);try await wait(bounded,requests[4]);precondition(bounded.value(requests[4]).movie != nil)
  print("PASS JAVLibrary shipping parser/schema, source ranks/page slices, auth headers/401, exact code/unique actors/ambiguous candidates, no MissAV enrichment, bounded queue/dedup/order, generation/account isolation, cancellation/reentry/retry")
 }
}
'''
with tempfile.TemporaryDirectory() as temp:
    path=Path(temp)
    swift='import Foundation\nimport Combine\n'+read('AVDB/Services/JavRankingCore.swift')+read('AVDB/Services/MissAVCore.swift')+client+source+read('AVDB/Services/MissAVMetadata.swift')+stubs
    (path/'Replay.swift').write_text(swift)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library','-D','STANDALONE_METADATA_REPLAY',str(path/'Replay.swift'),'-o',str(path/'replay')],check=True)
    subprocess.run([str(path/'replay')],check=True,timeout=30)
