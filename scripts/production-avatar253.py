import pathlib,subprocess,json,plistlib,time,os
R=pathlib.Path(__file__).resolve().parents[1];out=R/'evidence253';out.mkdir(exist_ok=True)
def read(p):return (R/p).read_text()
def decl(s,mark):
 start=s.index(mark);i=s.index('{',start)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]
stubs='''
@MainActor enum JavDBConstants { static let baseURL = "https://example.invalid" }
@MainActor final class APIClient { static let shared = APIClient(); var token: String? = "fixture-account-a" }
@MainActor enum ActorAvatarFallback {
 struct Result { let url: String? }
 static func existing(_ actor: Actor) -> String? { [actor.avatarURL,actor.coverURL].compactMap { $0 }.first { !$0.isEmpty } }
 static func resetCache() {}
 static func resolveMissing(actor:Actor,names:[String],existingFailed:Bool) async -> Result { Result(url:nil) }
}
'''
parts=['import Foundation',read('AVDB/Models/JSONFlex.swift'),decl(read('AVDB/Models/Movie.swift'),'public struct Actor:'),read('AVDB/Services/ActorAliasCatalog.swift'),read('AVDB/Services/JavRankingCore.swift').split('// MARK: - Controlled cache API')[0],read('AVDB/Services/JavBusPoster.swift'),stubs]
service=read('AVDB/Services/JavBusActorAvatar.swift')
base='\n'.join(parts)
mac=out/'ProductionMac253.swift';mac.write_text(base+'\n'+service.split('// MARK: - Native shared presentation')[0]+'\n'+read('scripts/ProductionLive253.swift')+'''
@main struct Main253 {
 @MainActor static func main() async throws {
  try await ProductionLive253.checks()
  let result = try await ProductionLive253.run()
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"evidence253/macos.json"))
 }
}
''')
subprocess.run(['swiftc','-parse-as-library',str(mac),'-o',str(out/'ProductionMac253')],check=True)
(out/'ActorAliasIndex.json').write_bytes((R/'AVDB/Resources/ActorAliasIndex.json').read_bytes())
subprocess.run([str(out/'ProductionMac253')],check=True,cwd=R)
uiStubs='''
import SwiftUI
import UIKit
@MainActor final class ImageLoader {
 static let shared = ImageLoader()
 func load(_ source:String,maxPixelSize:Int) async -> UIImage? { nil }
}
struct JavDBImage: View { let url:String?; var contentMode:ContentMode = .fill; var body: some View { Color.gray } }
'''
sim=out/'ProductionSimulator253.swift';sim.write_text(base+'\n'+uiStubs+'\n'+service+'\n'+read('scripts/ProductionLive253.swift')+'\n'+read('scripts/AvatarHost253.swift'))
def run(args,timeout=240):
 r=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 with (out/'simulator.log').open('a') as f:f.write('$ '+' '.join(args)+'\n'+r.stdout+'\n')
 if r.returncode:raise RuntimeError('command failed: '+str(args[:3]))
 return r.stdout.strip()
devices=json.loads(run(['xcrun','simctl','list','devices','available','-j']))['devices']
choices=[(rt,d) for rt,ds in devices.items() if 'iOS' in rt for d in ds if d.get('isAvailable') and 'iPhone' in d['name']];rt,d=choices[-1];udid=d['udid']
if d['state']!='Booted':run(['xcrun','simctl','boot',udid])
run(['xcrun','simctl','bootstatus',udid,'-b'])
app=out/'Avatar253.app';app.mkdir(exist_ok=True)
(app/'ActorAliasIndex.json').write_bytes((R/'AVDB/Resources/ActorAliasIndex.json').read_bytes())
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.avdb.diagnostics253','CFBundleExecutable':'Avatar253','CFBundleName':'Avatar253','CFBundlePackageType':'APPL','CFBundleVersion':'253','CFBundleShortVersionString':'1.0.2','LSRequiresIPhoneOS':True,'MinimumOSVersion':'17.0','UIDeviceFamily':[1,2],'UILaunchScreen':{}}))
sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path']);arch=run(['uname','-m'])
run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-sdk',sdk,'-target',arch+'-apple-ios17.0-simulator',str(sim),'-o',str(app/'Avatar253')])
run(['xcrun','simctl','install',udid,str(app)]);run(['xcrun','simctl','launch',udid,'org.avdb.diagnostics253'])
container=pathlib.Path(run(['xcrun','simctl','get_app_container',udid,'org.avdb.diagnostics253','data']))/'Documents'
for n in range(80):
 if (container/'failed.txt').exists():raise RuntimeError((container/'failed.txt').read_text())
 if (container/'ios-simulator.json').exists():break
 time.sleep(1)
else:raise RuntimeError('host timed out')
for name in ['ios-simulator.json','portrait253.jpg']:(out/name).write_bytes((container/name).read_bytes())
run(['xcrun','simctl','io',udid,'screenshot',str(out/'production-view253.png')])
(out/'simulator-status.json').write_text(json.dumps({'success':True,'runtime':rt,'device':d['name'],'actualProductionView':True},indent=2))
print((out/'ios-simulator.json').read_text())
from PIL import Image,ImageChops,ImageStat
screen=Image.open(out/'production-view253.png').convert('RGB')
# iPhone screenshots have 3 physical pixels per point; compare center 101pt
# of the actual visible View against separately fetched/decoded production bytes.
screen=screen.resize((screen.width//3,screen.height//3),Image.Resampling.LANCZOS)
portrait=Image.open(out/'portrait253.jpg').convert('RGB').resize((125,125),Image.Resampling.LANCZOS).crop((12,12,113,113))
best=(1e9,None)
for x in range(screen.width//2-64,screen.width//2-60):
 for y in range(100,screen.height-180):
  crop=screen.crop((x+12,y+12,x+113,y+113))
  score=sum(ImageStat.Stat(ImageChops.difference(crop,portrait)).mean)/3
  if score<best[0]:best=(score,[x,y,125,125])
assertion={'passed':best[0]<18,'meanAbsoluteRGBError':best[0],'threshold':18,'rectPoints':best[1],'method':'visible actual ActorAvatarArtwork screenshot compared with production JavBus ImageIO-decoded JPEG; center crop excludes edge interpolation'}
(out/'ui-pixel-assertion.json').write_text(json.dumps(assertion,indent=2))
assert assertion['passed'],assertion
