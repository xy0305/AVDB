from pathlib import Path
import subprocess,json,os,platform
r=Path(__file__).resolve().parents[1];out=r/'evidence-dmm266';out.mkdir(exist_ok=True)
assert platform.system()=='Darwin'
s=(r/'AVDB/Services/JavVersePolicy.swift').read_text();(out/'MovieResolver.swift').write_text(s.split('// External ranking names stay visible.')[0] + '\nenum DMMFixturePath { static let root = ' + json.dumps(str(r/'scripts/dmm-ranking-fixtures')) + ' }\n')
subprocess.run(['ruby',str(r/'scripts/setup-dmm-ui266.rb')],check=True,cwd=r)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices'];device=next(d for runtime,rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name'])
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)
subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True)
env=os.environ.copy();env['DMM_FIXTURE_ROOT']=str(r/'scripts/dmm-ranking-fixtures');env['SIMCTL_CHILD_DMM_FIXTURE_ROOT']=env['DMM_FIXTURE_ROOT']
# Host neutral dependencies are explicit; source parser/store/view and movie resolver are production Swift.
code=subprocess.call(['xcodebuild','test','-project',str(out/'DMM266.xcodeproj'),'-scheme','DMM266','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath',str(out/'Derived'),'-resultBundlePath',str(out/'DMM266.xcresult'),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO'],env=env,cwd=r)
(out/'status.json').write_text(json.dumps({'offline':True,'device':device,'exit':code,'boundaries':'production DMM view/store/parser and movie resolver; AVDB search, image, detail and 115 mocked; no real account/network'},ensure_ascii=False,indent=2))
if (out/'DMM266.xcresult').exists():subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(out/'DMM266.xcresult'),'--output-path',str(out/'screenshots')],check=True)
raise SystemExit(code)
