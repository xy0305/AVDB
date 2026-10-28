from pathlib import Path
import subprocess,json,time,platform
r=Path(__file__).resolve().parents[1];d=r/'evidence-lut83';d.mkdir(exist_ok=True)
assert platform.system()=='Darwin'
s=(r/'AVDB/Views/Player/NativeLUT.swift').read_text()
s=s.split('private final class OriginalFaceLandmarker:')[0]
s=s.replace('import MediaPipeTasksVision\n','').replace('import KSPlayer\n','')
s=s.replace('enum NativeLUT {','enum NativeLUT {\n    private static let fixtureLock = NSLock()\n    private static var fixtureCount = 0\n    static var fixtureBakeCount: Int { fixtureLock.lock(); defer { fixtureLock.unlock() }; return fixtureCount }')
s=s.replace('static func cube(_ p: LUTParameters) -> Data? {','static func cube(_ p: LUTParameters) -> Data? {\n        fixtureLock.lock(); fixtureCount += 1; fixtureLock.unlock()')
s+='\nextension NativeLUTController { var fixtureCache: LUTParameters? { cachedParameters } }\n'
(d/'Controller.swift').write_text(s)
ruby='''require 'xcodeproj'
r=ENV.fetch('GITHUB_WORKSPACE',Dir.pwd);d=File.join(r,'evidence-lut83')
p=Xcodeproj::Project.new(File.join(d,'LUT83.xcodeproj'));a=p.new_target(:application,'LUT83',:ios,'17.0')
['evidence-lut83/Controller.swift','scripts/LUT83NeutralHost.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f))) }
a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'AVDB/Resources/OriginalLUT.js')))
a.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='org.avdb.lut83neutral'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation']='YES'
end
p.save;s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.set_launch_target(a);s.save_as(p.path,'LUT83',true)
'''
(d/'setup.rb').write_text(ruby);subprocess.run(['ruby',str(d/'setup.rb')],check=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
device=next(v for k,rows in devices.items() if 'iOS' in k for v in rows if 'iPhone' in v['name'])
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)
subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True)
subprocess.run(['xcodebuild','build','-project',str(d/'LUT83.xcodeproj'),'-scheme','LUT83','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath',str(d/'Derived'),'CODE_SIGNING_ALLOWED=NO'],check=True)
app=d/'Derived/Build/Products/Debug-iphonesimulator/LUT83.app'
subprocess.run(['xcrun','simctl','install',device['udid'],str(app)],check=True)
subprocess.run(['xcrun','simctl','launch',device['udid'],'org.avdb.lut83neutral'],check=True)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device['udid'],'org.avdb.lut83neutral','data'],text=True).strip())
result=container/'Documents/result.json'
for _ in range(120):
 if result.exists():break
 time.sleep(1)
assert result.exists(),'No completion file; app crash or timeout'
o=json.loads(result.read_text());o['device']=device
(d/'result.json').write_text(json.dumps(o,indent=2));print(json.dumps(o,indent=2));assert o['passed']
