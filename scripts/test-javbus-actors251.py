import pathlib,subprocess,shutil,tempfile,os
R=pathlib.Path(__file__).resolve().parents[1]
def read(p): return (R/p).read_text()
def decl(s,mark):
 start=s.index(mark);i=s.index('{',start)+1; depth=1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]
assert 'ActorAvatarArtwork(actor: actor, numbers: [vm.movie?.number]' in read('AVDB/Views/Detail/MovieDetailView.swift')
assert 'ActorAvatarArtwork(actor: actor, numbers: Array(vm.movies' in read('AVDB/Views/Actors/ActorsView.swift')
for p in ['AVDB/Views/Rankings/RankingsView.swift','AVDB/Views/Search/SearchView.swift','AVDB/Views/User/UserView.swift']:
 assert 'ActorAvatarArtwork(actor: actor' in read(p),p
service=read('AVDB/Services/JavBusActorAvatar.swift').split('// MARK: - Native shared presentation')[0]
assert 'actorMovies(' not in service
ui=read('AVDB/Services/JavBusActorAvatar.swift').split('// MARK: - Native shared presentation')[1]
for refresh in ['numbers.joined', 'worksChanged', 'revision += 1', 'ImageLoader.shared.load', 'existingFailed: true']:
 assert refresh in ui,refresh
for safety in ['active >= 2','cache.count >= 120','600','86400','session.bytes(for:', 'http.statusCode == 200','httpShouldSetCookies = false','urlCredentialStorage = nil','768 * 1024','2 * 1024 * 1024','completionHandler(nil)', 'ActorAvatarRedirectPolicy', 'existingFailed', 'GfriendsPortraits', 'maxWorks = 6','Task.checkCancellation()']:
 assert safety in service,safety
if not shutil.which('swiftc'):
 print('PASS Swift source wiring/security checks; Swift runtime NOT RUN locally (requires macOS CI)');raise SystemExit(0)
stubs='''
@MainActor enum JavDBConstants { static let baseURL = "https://example.invalid" }
@MainActor final class APIClient { static let shared = APIClient(); var token: String? = "fixture-account-a" }
@MainActor enum ActorAvatarFallback {
 static func existing(_ actor: Actor) -> String? { [actor.avatarURL, actor.coverURL].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
'''
core=read('AVDB/Services/JavRankingCore.swift')
parts=['import Foundation',read('AVDB/Models/JSONFlex.swift'),decl(read('AVDB/Models/Movie.swift'),'public struct Actor:'),read('AVDB/Services/ActorAliasCatalog.swift'),core.split('// MARK: - Controlled cache API')[0],read('AVDB/Services/JavBusPoster.swift'),stubs,service,read('scripts/JavBusActorsRegression251.swift')]
with tempfile.TemporaryDirectory() as t:
 p=pathlib.Path(t)/'JavBusActors251.swift';p.write_text('\n'.join(parts));binary=p.with_suffix('')
 subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(binary)],check=True)
 shutil.copy(R/'AVDB/Resources/ActorAliasIndex.json', pathlib.Path(t)/'ActorAliasIndex.json')
 subprocess.run([str(binary)],check=True)
 if os.environ.get('JAVBUS_LIVE_PROBE')=='1':
  subprocess.run([str(binary),'--live'],check=True)
