from pathlib import Path
import subprocess, shutil, tempfile, sys, json
root=Path(__file__).resolve().parents[1]
policy=(root/'AVDB/Services/TPDBPolicy.swift').read_text()
service=(root/'AVDB/Services/TPDBArtworkService.swift').read_text()
settings=(root/'AVDB/Services/TPDBCoverSettings.swift').read_text()
ui=(root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
cache=(root/'AVDB/Services/DetailPosterCache.swift').read_text()
for s in ['config.httpCookieStorage = nil','config.urlCredentialStorage = nil','config.httpShouldSetCookies = false','config.urlCache = nil','session.bytes(for: request)','data.count < limit','ProcessInfo.processInfo.systemUptime < deadline','1024 * 1024','8 * 1024 * 1024','prefix(2)','TPDBPolicy.request','TPDBPolicy.permitsRedirect','TPDBPolicy.unique','TPDBPolicy.matches','negativeTTL: 30','cache.invalidate()','CGImageSourceGetStatus(source) == .statusComplete']:
 assert s in service,s
assert 'DetailPosterSelection' not in service and 'FrontPoster' not in service
assert 'Security' in settings and 'SecureField' in settings and 'WhenUnlockedThisDeviceOnly' in settings
assert 'defaults.bool(forKey:' in settings and 'token = ""' in settings
assert 'TPDBArtworkService.clear()' in settings
assert '.scaledToFit()' in ui and 'if movie.type == "2" { return .landscape }' in ui
assert 'tpdbArtworkKey == posterRequestKey' in ui and 'posterRequestKey == key' in ui
assert 'Pan115Client' not in service and 'print(' not in service+settings
pbx=(root/'AVDB.xcodeproj/project.pbxproj').read_text()
for f in ['TPDBPolicy.swift','TPDBCoverSettings.swift','TPDBArtworkService.swift']:
 assert pbx.count('path = '+f+';')==1
 assert pbx.count(f+' in Sources')==2
import plistlib
build = plistlib.loads((root/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion']
assert pbx.count(f'CURRENT_PROJECT_VERSION = {build};')==2
print('PASS TPDB static production auth isolation, bounded budget, Keychain, opt-in, landscape and fallback wiring')
swift=r'''
actor Probe {
 var calls = 0; var cancelled = 0
 func hit() { calls += 1 }
 func cancel() { cancelled += 1 }
 func count() -> (Int,Int) { (calls,cancelled) }
}
@main struct TPDBTests {
 static func main() async throws {
  let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let r = try JSONSerialization.jsonObject(with: fixture) as! [String:Any]
  let title = r["title"] as! String
  let official = r["url"] as! String
  let identity = TPDBPolicy.identity(type:"2",number:"Blackedraw.2026.10.13",title:title,date:"2026-10-13",minutes:35,official:official)!
  assert(TPDBPolicy.matches(r,identity))
  assert(TPDBPolicy.unique([r],identity) != nil)
  assert(TPDBPolicy.unique([r,r],identity) == nil)
  assert(TPDBPolicy.unique([],identity) == nil)
  let query: [String:Any] = ["data":[r],"meta":["current_page":1,"last_page":1,"total":1]]
  assert(TPDBPolicy.uniqueQuery(query,identity) != nil)
  assert(TPDBPolicy.uniqueQuery(["data":[r]],identity) == nil)
  assert(TPDBPolicy.uniqueQuery(["data":[r],"meta":["current_page":1,"last_page":2,"total":2]],identity) == nil)
  assert(TPDBPolicy.uniqueQuery(["data":[r],"meta":["current_page":1,"last_page":1,"total":2]],identity) == nil)
  for (key,value) in [("title","Different title"),("date","2026-10-12"),("id","not-a-uuid"),("url","https://www.vixen.com/videos/other-scene"),("external_id","blacked:other") ] {
   var bad=r; bad[key]=value; assert(!TPDBPolicy.matches(bad,identity),key)
  }
  var bad=r; bad["site"]=["name":"Blacked","short_name":"blacked"];assert(!TPDBPolicy.matches(bad,identity))
  bad=r;bad["duration"]=100;assert(!TPDBPolicy.matches(bad,identity))
  for type in ["0","1","3",""] { assert(TPDBPolicy.identity(type:type,number:"Blackedraw.2026.10.13",title:title,date:nil,minutes:35,official:nil)==nil) }
  for n in ["Blackedraw.2026.02.31","Unknown.2026.10.13","Blackedraw.2026.10.13.foo","ABF-378"] {
   assert(TPDBPolicy.identity(type:"2",number:n,title:title,date:nil,minutes:35,official:nil)==nil)
  }
  assert(TPDBPolicy.identity(type:"2",number:"Blackedraw.2026.10.13",title:title,date:"2026-10-14",minutes:35,official:nil)==nil)
  assert(TPDBPolicy.identity(type:"2",number:"Blackedraw.2026.10.13",title:nil,date:nil,minutes:35,official:nil)==nil)
  for (brand,name) in TPDBPolicy.brands {
   assert(TPDBPolicy.identity(type:"2",number:brand+".2026.10.13",title:title,date:nil,minutes:35,official:nil)?.brand==brand)
   var other=r;other["site"]=["name":name,"short_name":brand];other["url"]="https://www."+brand+".com/videos/scene";other["external_id"]=brand+":scene"
   let i=TPDBPolicy.identity(type:"2",number:brand+".2026.10.13",title:title,date:nil,minutes:35,official:nil)!
   assert(TPDBPolicy.matches(other,i))
  }
  let api=URL(string:"https://api.theporndb.net/scenes")!
  let image=TPDBPolicy.images(r).first!
  assert(TPDBPolicy.images(r).count==2)
  assert(!TPDBPolicy.imageAllowed(URL(string:r["poster"] as! String)!))
  let request=TPDBPolicy.request(api,token:"fake-test-token",timeout:1)!
  assert(request.value(forHTTPHeaderField:"Authorization")=="Bearer fake-test-token")
  assert(TPDBPolicy.request(image,token:"fake-test-token",timeout:1)==nil)
  let imageRequest=TPDBPolicy.request(image,token:nil,timeout:1)!
  assert(imageRequest.value(forHTTPHeaderField:"Authorization")==nil && imageRequest.value(forHTTPHeaderField:"Cookie")==nil)
  for u in ["http://api.theporndb.net/scenes","https://api.theporndb.net.evil.test/scenes","https://user@api.theporndb.net/scenes","https://api.theporndb.net:443/scenes","https://127.0.0.1/scenes","https://api.theporndb.net/scenes/nonsense","https://api.theporndb.net/user"] {
   assert(TPDBPolicy.request(URL(string:u)!,token:"fake-test-token",timeout:1)==nil)
  }
  for u in ["https://127.0.0.1/x.jpg","https://cdn.theporndb.net.evil.test/scene/x/background/x.jpg","https://cdn.theporndb.net/scene/x/background/c/x.jpg","https://cdn.theporndb.net/scene/x/background/upscale.jpg","http://cdn.theporndb.net/scene/x/background/x.jpg"] {
   assert(!TPDBPolicy.imageAllowed(URL(string:u)!))
  }
  assert(!TPDBPolicy.permitsRedirect(authenticated:true,count:1,target:api))
  assert(!TPDBPolicy.permitsRedirect(authenticated:true,count:1,target:image))
  assert(TPDBPolicy.permitsRedirect(authenticated:false,count:2,target:image))
  assert(!TPDBPolicy.permitsRedirect(authenticated:false,count:3,target:image))
  // Fake fetch uses the SAME production preflight/header policy, never the live token.
  func fakeFetch(_ url: URL, _ token: String?, _ code: Int, _ body: Data) -> [String:Any]? {
   guard TPDBPolicy.request(url,token:token,timeout:1) != nil, code==200,
         let value=try? JSONSerialization.jsonObject(with:body) as? [String:Any] else { return nil }
   return value
  }
  assert(fakeFetch(api,"invalid-test-token",401,fixture)==nil)
  assert(fakeFetch(api,"fake-test-token",200,Data("{partial".utf8))==nil)
  assert(fakeFetch(image,"fake-test-token",200,fixture)==nil)
  assert(TPDBPolicy.status(401).contains("401"))
  assert(TPDBPolicy.status(403).contains("不能据此断言"))
  assert(TPDBPolicy.status(429).contains("429"))
  assert(TPDBPolicy.completeLength(actual:17000,expected:2000,encoding:"gzip"))
  assert(TPDBPolicy.completeLength(actual:17000,expected:2000,encoding:"br"))
  assert(TPDBPolicy.completeLength(actual:2000,expected:2000,encoding:nil))
  assert(!TPDBPolicy.completeLength(actual:1999,expected:2000,encoding:nil))
  assert(!TPDBPolicy.completeLength(actual:1999,expected:2000,encoding:"identity"))
  let c=DetailPosterCache<Int>(positiveTTL:1,negativeTTL:0.03)
  let p=Probe()
  let slow: @Sendable () async -> Int? = {
   await p.hit()
   do { try await Task.sleep(nanoseconds:500_000_000);return 1 }
   catch { await p.cancel(); return nil }
  }
  let old=Task { await c.value(key:"account-A/gen-A",operation:slow) }
  try await Task.sleep(nanoseconds:30_000_000)
  c.invalidate()
  let oldResult=await old.value;assert(oldResult==nil)
  assert(c.snapshot(key:"account-A/gen-A").artwork==nil)
  let fresh=await c.value(key:"account-B/gen-B") { 2 }; assert(fresh==2)
  assert(c.snapshot(key:"account-A/gen-A").artwork==nil)
  let counts=await p.count();assert(counts.0==1 && counts.1==1)
  // Unknown metadata never fetches and remains the original fallback.
  var fallback="JavDB"
  if TPDBPolicy.identity(type:"2",number:nil,title:nil,date:nil,minutes:nil,official:nil) != nil { fallback="wrong" }
  assert(fallback=="JavDB")
  print("PASS actual Swift TPDB exact identity/ambiguity/brands/date, raw-vs-derived, host-only auth, redirect refusal, fake invalid-token/JSON fetch, generation cancellation and fallback")
 }
}
'''
if not shutil.which('swiftc'):
 print('NOTE actual TPDB Swift execution requires macOS CI; local static checks only')
else:
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'tests.swift').write_text(policy+'\n'+cache+'\n'+swift)
  subprocess.run(['swiftc','-parse-as-library',str(p/'tests.swift'),'-o',str(p/'test')],check=True)
  subprocess.run([str(p/'test'),str(root/'scripts/fixtures/tpdb-exact-scene.json')],check=True,timeout=30)
