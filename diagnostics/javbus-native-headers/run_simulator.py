#!/usr/bin/env python3
import subprocess as s, json, pathlib, time, os, traceback
out=pathlib.Path('evidence'); out.mkdir(exist_ok=True)
def run(args, timeout=180):
    r=s.run(args, text=True, stdout=s.PIPE, stderr=s.STDOUT, timeout=timeout)
    with (out/'simulator-build.log').open('a') as f: f.write('$ '+' '.join(args)+'\n'+r.stdout+'\n')
    if r.returncode: raise RuntimeError(f'command failed ({r.returncode}): {args[0:3]}')
    return r.stdout
status={'success':False,'phase':'discovery'}
try:
    devices=json.loads(run(['xcrun','simctl','list','devices','available','-j']))['devices']
    choices=[(runtime,d) for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if d.get('isAvailable') and 'iPhone' in d['name']]
    if not choices: raise RuntimeError('No available iPhone iOS simulator runtime installed')
    runtime,d=choices[-1]; udid=d['udid']; status.update(runtime=runtime,device=d['name'],udid=udid)
    status['phase']='boot'
    if d['state']!='Booted': run(['xcrun','simctl','boot',udid])
    run(['xcrun','simctl','bootstatus',udid,'-b'],240)
    status['phase']='build'
    app=pathlib.Path('NativeHeaderProbe.app'); app.mkdir(exist_ok=True)
    import plistlib
    with (app/'Info.plist').open('wb') as f: plistlib.dump({'CFBundleIdentifier':'org.diagnostics.JavBusNativeHeaders','CFBundleExecutable':'NativeHeaderProbe','CFBundleName':'NativeHeaderProbe','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','LSRequiresIPhoneOS':True,'MinimumOSVersion':'18.0','UIDeviceFamily':[1,2],'UILaunchScreen':{}},f)
    arch=run(['uname','-m']).strip()
    sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path']).strip()
    run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-sdk',sdk,'-target',arch+'-apple-ios18.0-simulator','diagnostics/javbus-native-headers/NativeProbe.swift','diagnostics/javbus-native-headers/SimulatorHost.swift','-o',str(app/'NativeHeaderProbe')],240)
    status['phase']='install-launch'
    run(['xcrun','simctl','install',udid,str(app)])
    run(['xcrun','simctl','launch',udid,'org.diagnostics.JavBusNativeHeaders'])
    container=pathlib.Path(run(['xcrun','simctl','get_app_container',udid,'org.diagnostics.JavBusNativeHeaders','data']).strip())
    status['phase']='await-result'
    for i in range(90):
        result=container/'Documents'/'ios-simulator.json'
        if result.exists():
            (out/'ios-simulator.json').write_bytes(result.read_bytes()); status.update(success=True,phase='completed'); break
        failure=container/'Documents'/'failed.txt'
        if failure.exists(): raise RuntimeError(failure.read_text())
        time.sleep(1)
    if not status['success']: raise RuntimeError('Simulator host did not produce JSON within 90 seconds')
except Exception as e:
    status['error']=str(e)
    (out/'simulator-exception.log').write_text(traceback.format_exc())
finally:
    (out/'simulator-status.json').write_text(json.dumps(status,indent=2))
print(json.dumps(status))
if not status['success']: raise SystemExit(1)
