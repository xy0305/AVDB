from pathlib import Path
import http.server,threading,subprocess,json,time,platform,functools
r=Path(__file__).resolve().parents[1]
d=r/'evidence-hls-runtime';d.mkdir(exist_ok=True)
assert platform.system()=='Darwin'
requests=[]
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self, fmt,*args):
  msg=fmt%args;requests.append(msg)
  (d/'http-requests.json').write_text(json.dumps(requests,indent=2))
 def end_headers(self):
  self.send_header('Cache-Control','no-cache');super().end_headers()
server=http.server.ThreadingHTTPServer(('127.0.0.1',18764),functools.partial(Handler,directory=str(r/'scripts/neutral-hls')))
threading.Thread(target=server.serve_forever,daemon=True).start()
ruby='''require 'xcodeproj'
r=ENV.fetch('GITHUB_WORKSPACE',Dir.pwd);d=File.join(r,'evidence-hls-runtime')
p=Xcodeproj::Project.new(File.join(d,'HLSRuntime.xcodeproj'));a=p.new_target(:application,'HLSRuntime',:ios,'17.0')
['AVDB/Views/Player/NativeHLSLUTSurface.swift','scripts/ProductionRendererHost.swift'].each { |f| a.source_build_phase.add_file_reference(p.main_group.new_file(File.join(r,f))) }
a.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='org.avdb.hlsruntime'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1,2'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['INFOPLIST_KEY_NSAppTransportSecurity']='{"NSAllowsArbitraryLoads":true}'
 c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
end
p.save;s=Xcodeproj::XCScheme.new;s.add_build_target(a);s.set_launch_target(a);s.save_as(p.path,'HLSRuntime',true)
'''
(d/'setup.rb').write_text(ruby);subprocess.run(['ruby',str(d/'setup.rb')],check=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
device=next(v for k,rows in devices.items() if 'iOS' in k for v in rows if 'iPhone' in v['name'])
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)
subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True)
subprocess.run(['xcodebuild','build','-project',str(d/'HLSRuntime.xcodeproj'),'-scheme','HLSRuntime','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath',str(d/'Derived'),'CODE_SIGNING_ALLOWED=NO'],check=True)
app=d/'Derived/Build/Products/Debug-iphonesimulator/HLSRuntime.app'
# Test-only ATS allowance lives solely in this generated host bundle, never in AVDB.
import plistlib
info=app/'Info.plist';pl=plistlib.loads(info.read_bytes());pl['NSAppTransportSecurity']={'NSAllowsArbitraryLoads':True};info.write_bytes(plistlib.dumps(pl))
subprocess.run(['xcrun','simctl','install',device['udid'],str(app)],check=True)
console=open(d/'app-console.log','w');launcher=subprocess.Popen(['xcrun','simctl','launch','--console-pty',device['udid'],'org.avdb.hlsruntime'],stdout=console,stderr=subprocess.STDOUT)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device['udid'],'org.avdb.hlsruntime','data'],text=True).strip())
result=container/'Documents/result.json';stage=container/'Documents/stage.txt';seen=set()
for _ in range(720):
 if stage.exists():
  value=stage.read_text().strip()
  if value not in seen:
   seen.add(value);subprocess.run(['xcrun','simctl','io',device['udid'],'screenshot',str(d/(value+'.png'))],check=True)
 if result.exists():break
 time.sleep(.25)
subprocess.run(['xcrun','simctl','io',device['udid'],'screenshot',str(d/'final.png')])
if not result.exists():
 with open(d/'runtime.log','w') as log:
  subprocess.run(['xcrun','simctl','spawn',device['udid'],'log','show','--last','4m','--style','compact','--predicate','process == "HLSRuntime"'],stdout=log,stderr=subprocess.STDOUT,timeout=40)
 raise AssertionError('No host result; see app-console.log/runtime.log')
o=json.loads(result.read_text());o['device']=device
segments=sorted({f'segment{i:02d}.ts' for i in range(6) if any(f'GET /segment{i:02d}.ts ' in line and ' 200 ' in line for line in requests)})
o['httpSegments']=segments;o['httpAllSix']=len(segments)==6;o['source']='HTTP HLS playlist.m3u8 / 6 MPEG-TS / H264+AAC / BT709 / 12 seconds'
o['passed']=o['passed'] and o['httpAllSix']
(d/'result.json').write_text(json.dumps(o,indent=2));print(json.dumps(o,indent=2));assert o['passed']
