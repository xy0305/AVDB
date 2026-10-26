from pathlib import Path
import subprocess,json,platform,os
R=Path(__file__).resolve().parents[1]; O=R/'evidence261';O.mkdir(exist_ok=True)
assert platform.system()=='Darwin','Requires real Xcode simulator'
s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text()
(O/'Identity.swift').write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
files=['AVDB/Services/PlaybackDiagnostic.swift','AVDB/Services/JavRankingCore.swift','AVDB/Services/MissAVCore.swift','AVDB/Services/OnlinePlaybackCore.swift','AVDB/Services/OnlineAdditionalProviders.swift','AVDB/Services/DetailOnlineAdapters.swift','AVDB/Services/TangxinCore.swift','AVDB/Views/TangxinView.swift','AVDB/Views/ContentView.swift','AVDB/Views/AVDBNativeTabBar.swift','scripts/TangxinFixtures261.swift','scripts/TangxinUIHost261.swift','evidence261/Identity.swift']
ruby="""require 'xcodeproj'
r=ENV.fetch('GITHUB_WORKSPACE',Dir.pwd); o=File.join(r,'evidence261');p=Xcodeproj::Project.new(File.join(o,'Tangxin261.xcodeproj'))
a=p.new_target(:application,'Tangxin261',:ios,'17.0')
FILES.each {|f|a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f)))}
t=p.new_target(:ui_test_bundle,'TangxinUITests261',:ios,'17.0');t.add_dependency(a)
t.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'scripts/TangxinUITests261.swift')))
[a,t].each do |target|
 target.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='org.avdb.'+target.name
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['SWIFT_OPTIMIZATION_LEVEL']='-Onone'
 c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=''
 c.build_settings['ENABLE_PREVIEWS']='NO'
 end
end
t.build_configurations.each {|c|c.build_settings['TEST_TARGET_NAME']='Tangxin261'}
p.save;s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.add_build_target(t);s.add_test_target(t);s.set_launch_target(a);s.save_as(p.path,'Tangxin261',true)
""".replace('FILES',repr(files))
(O/'setup.rb').write_text(ruby)
subprocess.run(['ruby',str(O/'setup.rb')],check=True,cwd=R)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices'];status={}
for kind in ['iPhone','iPad']:
 choices=[d for rt,ds in devices.items() if 'iOS' in rt for d in ds if kind in d['name']];assert choices
 d=choices[0]
 if d['state']!='Booted':subprocess.run(['xcrun','simctl','boot',d['udid']],check=True)
 subprocess.run(['xcrun','simctl','bootstatus',d['udid'],'-b'],check=True)
 if kind == 'iPhone':
  sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
  binary=O/'model261'
  model_files=files[:8]+['scripts/TangxinFixtures261.swift','evidence261/Identity.swift','scripts/TangxinModelRegression261.swift']
  subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-parse-as-library','-swift-version','5','-target',platform.machine()+'-apple-ios17.0-simulator','-sdk',sdk,*[str(R/f) for f in model_files],'-o',str(binary)],check=True)
  subprocess.run(['xcrun','simctl','spawn',d['udid'],str(binary)],check=True,timeout=60)
 xc=O/(kind+'.xcresult');shots=O/(kind+'-screenshots');shots.mkdir(exist_ok=True)
 code=subprocess.call(['xcodebuild','test','-project',str(O/'Tangxin261.xcodeproj'),'-scheme','Tangxin261','-configuration','Release','-destination','platform=iOS Simulator,id='+d['udid'],'-derivedDataPath',str(O/'Derived'),'-resultBundlePath',str(xc),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO'],cwd=R)
 if xc.exists():subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(xc),'--output-path',str(shots)],check=True)
 status[kind]={'name':d['name'],'exit':code,'synthetic':True,'realPlaybackVerified':False}
 (O/'status.json').write_text(json.dumps(status,indent=2))
 if code:raise SystemExit(code)
print('PASS262 real iPhone + iPad production navigation and empty-state/manual-next UI; synthetic source only, no playback')
