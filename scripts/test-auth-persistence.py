#!/usr/bin/env python3
"""Execute the production AppState with isolated defaults and mocked transport."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
def declaration(text, marker):
    start=text.index(marker); end=text.index('{',start)+1; depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
app=(root/'AVDB/AVDBApp.swift').read_text()
model=declaration((root/'AVDB/Models/User.swift').read_text(),'public struct User:')
error=declaration((root/'AVDB/Networking/APIClient.swift').read_text(),'public enum JavDBError:')
source='''import Foundation
import Combine
import Network
import CryptoKit
'''+model+'\n'+error+'''
final class APIClient { static let shared = APIClient(); var token: String? }
@MainActor final class JavDBSDK {
 static let shared = JavDBSDK()
 func profile() async throws -> User { fatalError("must inject transport") }
 func logout() { APIClient.shared.token = nil }
}
'''+app[app.index('@MainActor\nfinal class AppState'):]+'''
@main struct Regression {
 @MainActor static func main() async throws {
  let name = "avdb.auth.test." + UUID().uuidString
  let store = UserDefaults(suiteName: name)!
  defer { store.removePersistentDomain(forName: name) }
  let client = APIClient.shared
  client.token = "synthetic-A"
  let user = try JSONDecoder().decode(User.self, from: Data("{\\"id\\":8,\\"username\\":\\"Example\\",\\"email\\":\\"private@example.invalid\\",\\"avatar_url\\":\\"https://invalid/?token=private\\",\\"bio\\":\\"private\\"}".utf8))
  var calls = 0
  var fail = false
  var failuresRemaining = 0
  var beforeReturn: (() -> Void)?
  func make() -> AppState {
   AppState(defaults: store, fetchProfile: {
    calls += 1; await Task.yield(); beforeReturn?()
    if failuresRemaining > 0 { failuresRemaining -= 1; throw URLError(.notConnectedToInternet) }
    if fail { throw URLError(.timedOut) }
    return user
   }, pause: { _ in await Task.yield() }, observeNetwork: false)
  }
  let initial = make(); await initial.restoreTask?.value
  assert(initial.currentUser?.id == 8 && initial.sessionStatus == .validated)
  let data = store.dictionaryRepresentation().filter { $0.key.hasPrefix("avdb.profile.") }
  assert(data.count == 1)
  let bytes = data.values.first as! Data
  let json = String(data: bytes, encoding: .utf8)!
  assert(!json.contains("email") && !json.contains("avatar") && !json.contains("bio") && !json.contains("synthetic"))
  assert(!data.keys.first!.contains("synthetic"))
  fail = true; calls = 0
  let cached = make()
  assert(cached.currentUser?.id == 8 && cached.sessionStatus == .cached)
  cached.resumeValidation(); await cached.restoreTask?.value
  assert(calls == 4 && cached.currentUser?.id == 8)
  fail = false; cached.resumeValidation(); await cached.restoreTask?.value
  assert(cached.sessionStatus == .validated)
  client.token = "synthetic-B"; fail = true; calls = 0
  cached.restoreLogin()
  assert(cached.currentUser == nil)
  await cached.restoreTask?.value
  assert(calls == 4 && cached.sessionStatus == .unavailable)
  fail = false; cached.resumeValidation(); await cached.restoreTask?.value
  assert(cached.currentUser?.id == 8)
  beforeReturn = { client.token = "synthetic-C" }
  let race = make(); await race.restoreTask?.value
  assert(race.currentUser?.id == 8) // B cache only; late result cannot validate C.
  assert(race.sessionStatus == .cached)
  beforeReturn = nil
  let unauthorized = AppState(defaults: store, fetchProfile: { throw JavDBError.httpError(401,"mock") }, pause: {_ in}, observeNetwork: false)
  await unauthorized.restoreTask?.value
  assert(unauthorized.sessionStatus == .needsReauth && unauthorized.currentUser == nil)
  assert(client.token == "synthetic-C")
  unauthorized.resumeValidation(); assert(unauthorized.restoreTask == nil)
  client.token = "synthetic-B"
  let loggedOut = make(); loggedOut.logout(); await Task.yield()
  assert(loggedOut.currentUser == nil && client.token == nil)
  client.token = "synthetic-B"; fail = true
  let noSnapshot = make(); assert(noSnapshot.currentUser == nil)
  await noSnapshot.restoreTask?.value
  client.token = "synthetic-new-account"; fail = false; failuresRemaining = 2; calls = 0
  let automatic = make()
  assert(automatic.currentUser == nil)
  await automatic.restoreTask?.value
  assert(calls == 3 && automatic.sessionStatus == .validated && automatic.currentUser?.id == 8)
  automatic.acceptLogin(user)
  assert(automatic.sessionStatus == .validated)
  automatic.resumeValidation(); automatic.logout(); await Task.yield()
  assert(automatic.currentUser == nil && automatic.sessionStatus == .signedOut)
  print("PASS production AppState: cold cache, sanitized snapshot, single flight, bounded retry, recovery, account switch/epoch, logout, 401")
 }
}
'''
if not shutil.which('swiftc'):
 print('SKIP runtime: swiftc unavailable; macOS CI executes production AppState')
else:
 with tempfile.TemporaryDirectory() as d:
  p=Path(d); (p/'Auth.swift').write_text(source)
  subprocess.run(['swiftc','-parse-as-library',str(p/'Auth.swift'),'-o',str(p/'auth')],check=True)
  subprocess.run([str(p/'auth')],check=True)
