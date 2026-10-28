from pathlib import Path
import http.server,threading,subprocess,json,time,platform,functools,plistlib
r=Path(__file__).resolve().parents[1]
d=r/'evidence-hls-app';d.mkdir(exist_ok=True)
assert platform.system()=='Darwin'
requests=[]
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self, fmt,*args):
  requests.append(fmt%args);(d/'http-requests.json').write_text(json.dumps(requests,indent=2))
 def end_headers(self):
  self.send_header('Cache-Control','no-cache');super().end_headers()
server=http.server.ThreadingHTTPServer(('127.0.0.1',18764),functools.partial(Handler,directory=str(r/'scripts/neutral-hls')))
threading.Thread(target=server.serve_forever,daemon=True).start()
ruby='''require 'xcodeproj'
r=ENV.fetch('GITHUB_WORKSPACE',Dir.pwd);d=File.join(r,'evidence-hls-app')
p=Xcodeproj::Project.new(File.join(d,'HLSApp.xcodeproj'));a=p.new_target(:application,'HLSApp',:ios,'17.0')
['AVDB/Views/Player/NativeHLSLUTSurface.swift','AVDB/Views/Player/NativeLUT.swift','scripts/ProductionLUTOnlineHost.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f))) }
['OriginalLUT.js','Enhancement.metallib'].each { |f| a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'AVDB/Resources',f))) }
production=Xcodeproj::Project.open(File.join(r,'AVDB.xcodeproj'))
original=production.root_object.package_references.find { |x| x.repositoryURL.include?('KSPlayer') }
ref=p.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference);ref.repositoryURL=original.repositoryURL;ref.requirement=original.requirement
p.root_object.package_references << ref
product=p.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency);product.package=ref;product.product_name='KSPlayer'
a.package_product_dependencies << product
build=p.new(Xcodeproj::Project::Object::PBXBuildFile);build.product_ref=product;a.frameworks_build_phase.files << build
a.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='org.avdb.hlsapp'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
end
p.save;s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.set_launch_target(a);s.save_as(p.path,'HLSApp',true)
'''
(d/'setup.rb').write_text(ruby);subprocess.run(['ruby',str(d/'setup.rb')],check=True)
(d/'Podfile').write_text("platform :ios, '17.0'\nproject 'HLSApp.xcodeproj'\ntarget 'HLSApp' do\n pod 'MediaPipeTasksVision', '0.10.14'\nend\n")
subprocess.run(['pod','install','--repo-update'],cwd=d,check=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
device=next(v for k,rows in devices.items() if 'iOS' in k for v in rows if 'iPhone' in v['name'])
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)
subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True)
with (d/'build.log').open('w') as log:
 result=subprocess.run(['xcodebuild','build','-workspace',str(d/'HLSApp.xcworkspace'),'-scheme','HLSApp','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath',str(d/'Derived'),'CODE_SIGNING_ALLOWED=NO'],stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
 print((d/'build.log').read_text()[-24000:]);raise SystemExit(result.returncode)
app=d/'Derived/Build/Products/Debug-iphonesimulator/HLSApp.app'
info=app/'Info.plist';pl=plistlib.loads(info.read_bytes());pl['NSAppTransportSecurity']={'NSAllowsArbitraryLoads':True};info.write_bytes(plistlib.dumps(pl))
subprocess.run(['xcrun','simctl','install',device['udid'],str(app)],check=True)
console=open(d/'app-console.log','w');launcher=subprocess.Popen(['xcrun','simctl','launch','--console-pty',device['udid'],'org.avdb.hlsapp'],stdout=console,stderr=subprocess.STDOUT)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device['udid'],'org.avdb.hlsapp','data'],text=True).strip())
result=container/'Documents/result.json';stage=container/'Documents/stage.txt';seen=set()
for _ in range(960):
 if stage.exists():
  value=stage.read_text().strip()
  if value not in seen:
   seen.add(value);subprocess.run(['xcrun','simctl','io',device['udid'],'screenshot',str(d/(value+'.png'))],check=True)
   (container/'Documents/ack.txt').write_text(value)
 if result.exists():break
 time.sleep(.25)
if not result.exists():
 print((d/'app-console.log').read_text()[-12000:]);raise AssertionError('No production controller host result')
o=json.loads(result.read_text());o['device']=device
o['httpSegments']=sorted({f'segment{i:02d}.ts' for i in range(6) if any(f'GET /segment{i:02d}.ts ' in line and ' 200 ' in line for line in requests)})
o['httpAllSix']=len(o['httpSegments'])==6;o['passed']=o['passed'] and o['httpAllSix']
(d/'result.json').write_text(json.dumps(o,indent=2));print(json.dumps(o,indent=2))
for f in [d/'Podfile.lock',d/'HLSApp.xcworkspace/xcshareddata/swiftpm/Package.resolved',d/'HLSApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',d/'Derived/SourcePackages/workspace-state.json']:
 if f.exists(): (d/('resolved-'+f.name)).write_bytes(f.read_bytes())
assert o['passed']
