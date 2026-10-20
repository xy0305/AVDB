"""Execute production RankingsViewModel, TOP250 SDK and Movie decoder with mock transport.
Synthetic neutral success fixtures are NOT live API evidence. auth fixture is a live anonymous response.
"""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
view=(root/'AVDB/Views/Rankings/RankingsView.swift').read_text()
sdk=(root/'AVDB/Services/JavDBSDK.swift').read_text()
api=(root/'AVDB/Networking/APIClient.swift').read_text()
vm=view[view.index('@MainActor\nfinal class RankingsViewModel'):view.index('\nstruct Top250FilterSheet:')]
tab=view[view.index('enum RankingTab:'):view.index('\nstruct RankingsView:')]
top=sdk[sdk.index('    public func topMovies('):sdk.index('    /// 按标签')]
response=api[api.index('public struct JavDBResponse'):api.index('/// JAVDB HTTP 客户端\n')]
support='''
import Foundation
import Combine
public enum CoverURLBuilder { public static func coverURLs(for n:String?) -> (poster:String?,backdrop:String?) { (nil,nil) } }
enum RankPeriod: String { case daily, weekly, monthly }
@MainActor final class APIClient {
 static let shared=APIClient()
 var raw=Data()
 var query:[String:String]=[:]
 var path=""
 func get<T:Decodable>(_ path:String,query:[String:String],useToken:Bool=false) async throws -> T {
  self.path=path;self.query=query
  return try JSONDecoder().decode(T.self,from:raw)
 }
}
@MainActor final class JavDBSDK {
 static let shared=JavDBSDK()
 let client=APIClient.shared
 func rememberMovies(_ m:[Movie]) {}
 func actorRankings(type:String,period:String,page:Int) async throws -> [Actor] { [] }
 func rankings(type:String,period:String,page:Int) async throws -> [Movie] { [] }
 func playbackRankings(filterBy:String,period:String,page:Int) async throws -> [Movie] { [] }
'''+top+'}\n'
external=(root/'AVDB/Services/ExternalLibraryClient.swift').read_text().split('final class ExternalLibraryClient')[0]
source=support+response+'\n'+(root/'AVDB/Services/JavRankingCore.swift').read_text()+'\n'+(root/'AVDB/Services/CatalogueMetadata.swift').read_text().split('private final class CatalogueRedirectBlocker:')[0]+'\n'+external+'\n'+(root/'AVDB/Models/JSONFlex.swift').read_text()+'\n'+(root/'AVDB/Models/Movie.swift').read_text()+'\n'+tab+'\n'+vm+'\n'+(root/'scripts/RankingsRegression.swift').read_text()
assert 'try? await sdk.topMovies' not in view
assert 'guard resp.isSuccess' in top
assert 'guard let decoded = resp.data?.movies' in top
assert 'setToken(' not in top and 'setToken(' not in vm
assert 'native-ranking-error' in view and '暂无符合条件的作品' in view
if shutil.which('swiftc'):
 with tempfile.TemporaryDirectory() as tmp:
  p=Path(tmp)/'ranking.swift';p.write_text(source)
  subprocess.run(['swiftc','-parse-as-library',str(p),'-o',tmp+'/ranking'],check=True)
  subprocess.run([tmp+'/ranking'],check=True)
else: print('Swift unavailable locally: production VM/decoder executable tests deferred to macOS CI')
print('PASS TOP250 error/no-logout/render-state source contracts')
