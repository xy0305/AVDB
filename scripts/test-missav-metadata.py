"""Execute shipping metadata queue with isolated backend adapters, never live accounts."""
from pathlib import Path
import subprocess, tempfile, shutil
root=Path(__file__).resolve().parents[1]
if not shutil.which('swiftc'):
    print('Metadata queue Swift execution requires macOS CI');raise SystemExit(0)
stubs=r'''
import Foundation
import Combine
struct Movie { let id: String }
struct Actor { let id: String; var name: String?; var nameZht: String?; var otherName: String? }
struct JRVideo { let path: String; let code: String }
struct MissAVActress { let path: String; let aliases: [String] }
enum JRPolicy { static func exactCode(_ code: String) -> String? { code.isEmpty ? nil : code } }
enum MissAVIdentity { static func exact(_ a: [String], _ b: [String?]) -> Bool { false } }
@MainActor final class APIClient { static let shared = APIClient(); var token: String? = nil }
@MainActor final class MissAVSource {
 static let shared = MissAVSource(); var generation=0
 struct Detail { let video: JRVideo }
 func detail(_ v: JRVideo) async throws -> Detail { Detail(video:v) }
 func actressAliases(_ a: MissAVActress) async throws -> [String] { [] }
}
@MainActor final class JavDBSDK {
 static let shared=JavDBSDK()
 func exactMovie(code: String, verifyAllPages: Bool) async throws -> Movie? { nil }
 func searchActors(keyword: String, page: Int) async throws -> [Actor] { [] }
}
'''
tests=r'''
Task { @MainActor in
 var active=0, maximum=0, calls=0
 let q=MissAVMetadata(resolver: { request in
  active += 1; calls += 1; maximum=max(maximum,active)
  defer { active -= 1 }
  try await Task.sleep(nanoseconds: 30_000_000)
  return MissAVMetadata.Result(movie: Movie(id:request.key), loading:false)
 })
 let requests=(1...6).map { MissAVMetadata.Request.movie(JRVideo(path:"/\($0)",code:"TEST-\($0)")) }
 q.reset()
 for r in requests { q.enqueue(r); q.enqueue(r) }
 for _ in 0..<100 {
  if requests.allSatisfy({ q.value($0).movie != nil }) { break }
  try! await Task.sleep(nanoseconds: 30_000_000)
 }
 precondition(maximum == 2 && calls == 6, "bounded concurrency and dedup")
 precondition(requests.allSatisfy { q.value($0).movie?.id == $0.key }, "identity ordered results")
 q.reset();q.enqueue(requests[0]);q.suspend()
 try! await Task.sleep(nanoseconds: 100_000_000)
 precondition(q.results.isEmpty,"cancelled response discarded")
 q.enqueue(requests[0])
 for _ in 0..<100 {
  if q.value(requests[0]).movie != nil { break }
  try! await Task.sleep(nanoseconds: 30_000_000)
 }
 precondition(q.value(requests[0]).movie?.id == requests[0].key,"return requeues unfinished entries")
 q.reset();q.enqueue(requests[1]);APIClient.shared.token="synthetic-account-change"
 q.enqueue(requests[2])
 for _ in 0..<100 {
  if q.value(requests[2]).movie != nil { break }
  try! await Task.sleep(nanoseconds: 30_000_000)
 }
 precondition(q.value(requests[1]).movie == nil && q.value(requests[2]).movie?.id == requests[2].key,"account reset rejects stale result")
 print("PASS shipping metadata queue: 2 concurrency, dedup, identity, cancellation, reentry, account isolation")
 exit(0)
}
RunLoop.main.run(until:Date().addingTimeInterval(5));fatalError("queue timeout")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(stubs+(root/'AVDB/Services/MissAVMetadata.swift').read_text()+tests)
 subprocess.run(['swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'queue')],check=True)
 subprocess.run([str(p/'queue')],check=True,timeout=10)
