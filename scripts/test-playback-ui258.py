from pathlib import Path
import json,subprocess,sys,platform
R=Path(__file__).resolve().parents[1];out=R/'evidence258';out.mkdir(exist_ok=True)
def run(a,**kw): return subprocess.run(a,check=True,**kw)
s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text()
(out/'Identity258.swift').write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
assert platform.system()=='Darwin', 'Real XCTest requires Xcode; no Linux screenshot substitutes'
run(['ruby',str(R/'scripts/setup-playback-ui258.rb')],cwd=R)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
selected={}
for kind in ['iPhone','iPad']:
 choices=[d for rt,ds in devices.items() if 'iOS' in rt for d in ds if kind in d['name']]
 assert choices;d=choices[0]; selected[kind]=d
 if d['state']!='Booted':run(['xcrun','simctl','boot',d['udid']])
 run(['xcrun','simctl','bootstatus',d['udid'],'-b'])
 xc=out/(kind+'.xcresult'); attachments=out/(kind+'-screenshots');attachments.mkdir(exist_ok=True)
 code=subprocess.call(['xcodebuild','test','-project',str(out/'Playback258.xcodeproj'),'-scheme','Playback258','-configuration','Debug','-destination','platform=iOS Simulator,id='+d['udid'],'-derivedDataPath',str(out/'Derived'),'-resultBundlePath',str(xc),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO'],cwd=R)
 if xc.exists():run(['xcrun','xcresulttool','export','attachments','--path',str(xc),'--output-path',str(attachments)])
 selected[kind]['testExit']=code
 (out/'ui258-status.json').write_text(json.dumps(selected,indent=2))
 if code:sys.exit(code)
print('PASS258 real XCTest production compact actions and panel: iPhone + iPad; neutral loader only; no site or media access')
