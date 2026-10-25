from pathlib import Path
import subprocess,json,tempfile,platform
R=Path(__file__).resolve().parents[1]
def run(args,**kw):return subprocess.run(args,check=True,**kw)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
choices=[d for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if 'iPhone' in d['name']]
assert choices,'No iOS simulator available'
d=choices[0];print('SIMULATOR',d,flush=True)
if d['state']!='Booted':run(['xcrun','simctl','boot',d['udid']])
run(['xcrun','simctl','bootstatus',d['udid'],'-b'])
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);identity=p/'Identity.swift';s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text();identity.write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
 files=['AVDB/Services/JavRankingCore.swift','AVDB/Services/MissAVCore.swift','AVDB/Services/OnlinePlaybackCore.swift','AVDB/Services/OnlineAdditionalProviders.swift','AVDB/Services/DetailOnlineAdapters.swift','AVDB/Views/Player/OnlinePlaybackPanel.swift','scripts/OnlineSafetyRegression255.swift','scripts/OnlineCompatibilityRegression256.swift','scripts/OnlineProbe256.swift']
 fixture=p/'Fixture254.swift';fixture.write_text((R/'scripts/OnlineRegression254.swift').read_text().replace('@main struct OnlineRegression254','struct OnlineRegression254'))
 sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
 binary=p/'probe256'
 run(['xcrun','--sdk','iphonesimulator','swiftc','-parse-as-library','-target',platform.machine()+'-apple-ios17.0-simulator','-sdk',sdk,'-swift-version','5','-D','ONLINE_CORE_TEST',str(identity),str(fixture),*[str(R/f) for f in files],'-o',str(binary)])
 run(['xcrun','simctl','spawn',d['udid'],str(binary)],timeout=300)
