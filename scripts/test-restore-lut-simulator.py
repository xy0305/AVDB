from pathlib import Path
import subprocess,json,time,platform
r=Path(__file__).resolve().parents[1];d=r/'evidence-restore-lut';d.mkdir(exist_ok=True)
assert platform.system()=='Darwin'
s=(r/'AVDB/Views/Player/NativeLUT.swift').read_text()
# Retain the actual production face model, panel and dedicated OS thread.
s=s.replace('import KSPlayer\n','')
(d/'Controller.swift').write_text(s)
ruby='''require 'xcodeproj'
r=ENV.fetch('GITHUB_WORKSPACE',Dir.pwd);d=File.join(r,'evidence-restore-lut')
p=Xcodeproj::Project.new(File.join(d,'RestoreLUT.xcodeproj'));a=p.new_target(:application,'RestoreLUT',:ios,'17.0')
['evidence-restore-lut/Controller.swift','scripts/RestoreLUTNeutralHost.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f))) }
a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'AVDB/Resources/OriginalLUT.js')))
a.resources_build_phase.add_file_reference(p.main_group.new_file(File.join(r,'AVDB/Resources/face_landmarker.task')))
a.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='org.avdb.restorelutneutral'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation']='YES'
end
p.save;s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.set_launch_target(a);s.save_as(p.path,'RestoreLUT',true)
'''
(d/'setup.rb').write_text(ruby);subprocess.run(['ruby',str(d/'setup.rb')],check=True)
(d/'Podfile').write_text("platform :ios, '17.0'\nproject 'RestoreLUT.xcodeproj'\ntarget 'RestoreLUT' do\n pod 'MediaPipeTasksVision', '0.10.14'\nend\n")
subprocess.run(['pod','install','--repo-update'],cwd=d,check=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
device=next(v for k,rows in devices.items() if 'iOS' in k for v in rows if 'iPhone' in v['name'])
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)
subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True)
subprocess.run(['xcodebuild','build','-workspace',str(d/'RestoreLUT.xcworkspace'),'-scheme','RestoreLUT','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath',str(d/'Derived'),'CODE_SIGNING_ALLOWED=NO'],check=True)
app=d/'Derived/Build/Products/Debug-iphonesimulator/RestoreLUT.app'
subprocess.run(['xcrun','simctl','install',device['udid'],str(app)],check=True)
console=open(d/'app-console.log','w');launcher=subprocess.Popen(['xcrun','simctl','launch','--console-pty',device['udid'],'org.avdb.restorelutneutral'],stdout=console,stderr=subprocess.STDOUT)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device['udid'],'org.avdb.restorelutneutral','data'],text=True).strip())
result=container/'Documents/result.json'
for _ in range(240):
 if result.exists():break
 time.sleep(1)
progress=container/'Documents/progress.txt'
if progress.exists():print('Last fixture stage:',progress.read_text())
subprocess.run(["xcrun","simctl","io",device["udid"],"screenshot",str(d/"native-panel.png")])
if not result.exists():
 try:
  with open(d/'simulator-runtime.log','w') as log:
   subprocess.run(['xcrun','simctl','spawn',device['udid'],'log','show','--last','5m','--style','compact','--predicate','process == "RestoreLUT"'],stdout=log,stderr=subprocess.STDOUT,timeout=30)
 except subprocess.TimeoutExpired:pass
 for report in (Path.home()/'Library/Logs/DiagnosticReports').glob('RestoreLUT*'):
  if report.is_file():(d/'crash.log').write_text(report.read_text(errors='replace')[:200000])
assert result.exists(),'No completion file; app crash or timeout; see app-console/runtime/crash logs'

o=json.loads(result.read_text());o['device']=device
(d/'result.json').write_text(json.dumps(o,indent=2));print(json.dumps(o,indent=2));assert o['passed']

subprocess.run(["xcrun","simctl","io",device["udid"],"screenshot",str(d/"native-panel.png")],check=True)
