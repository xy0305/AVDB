#!/usr/bin/env python3
"""Build 290 simulator screenshots + UI e2e: production AICoverSettingsSection / AICoverEnhanceModel / AICoverCloud client
against two local mocks of the R2 Worker (fast with the IPX-706 object preloaded, slow = 1.2 s per request (well under the 2.5 s budget on slow CI simulators)). The preloaded
"cloud" image is a plain 4× resize of the fixture (stand-in for a stored enhancement), not model output. Checks that the
miss path PUTs the local result to the mock. The real app key is not used here."""
from pathlib import Path
import json, platform, shutil, subprocess, sys, time
r = Path(__file__).resolve().parents[1]; out = r / 'evidence-ai290ui'; out.mkdir(exist_ok=True)
assert platform.system() == 'Darwin'
fixture = r / 'scripts/fixtures286/ipx706_front_378x538.jpg'
stand_in = out / 'cloud_standin_1512x2152.jpg'
subprocess.run(['sips', '-z', '2152', '1512', str(fixture), '--out', str(stand_in)], check=True, capture_output=True)
logs = {'fast': out / 'mock-fast.jsonl', 'slow': out / 'mock-slow.jsonl'}
for l in logs.values(): l.unlink(missing_ok=True)
pre = f'nomos1/IPX-706_378x538.jpg={stand_in}'
mw = str(r / 'scripts/cloud290/mock_worker.py')
servers = [subprocess.Popen([sys.executable, mw, '8791', 'test-key', '--log', str(logs['fast']), '--preload', pre]),
           subprocess.Popen([sys.executable, mw, '8792', 'test-key', '--delay', '1.2', '--log', str(logs['slow']), '--preload', pre])]
time.sleep(1)
try:
    subprocess.run(['ruby', str(r / 'scripts/cloud290/setup-ai-ui290.rb')], check=True, cwd=r)
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
    phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
    device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
    if device['state'] != 'Booted':
        subprocess.run(['defaults', 'write', 'com.apple.iphonesimulator', 'ConnectHardwareKeyboard', '-bool', 'false'], check=False)
        subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
    subprocess.run(['xcrun', 'simctl', 'status_bar', device['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'], check=False)
    code = subprocess.call(['xcodebuild', 'test', '-project', str(out / 'AI290.xcodeproj'), '-scheme', 'AI290',
                            '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(out / 'Derived'),
                            '-resultBundlePath', str(out / 'AI290.xcresult'), '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO'], cwd=r)
finally:
    for s in servers: s.terminate()
raw = out / 'attachments'
if (out / 'AI290.xcresult').exists():
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(out / 'AI290.xcresult'), '--output-path', str(raw)], check=False)
shots = out / 'shots'; shots.mkdir(exist_ok=True)
named = []
manifest = raw / 'manifest.json'
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for att in test.get('attachments', []):
            src = raw / att['exportedFileName']
            name = (att.get('suggestedHumanReadableName') or att['exportedFileName'])
            if not name[:2].isdigit() or src.suffix.lower() not in ('.png', '.jpg', '.jpeg'): continue
            dst = shots / (name.split('_0_')[0] + src.suffix); shutil.copy(src, dst); named.append(dst.name)
reqs = {k: [json.loads(x) for x in v.read_text().splitlines()] if v.exists() else [] for k, v in logs.items()}
puts = [q for q in reqs['fast'] if q['method'] == 'PUT']
gets = [q for q in reqs['fast'] + reqs['slow'] if q['method'] == 'GET']
status = {'device': device['name'], 'exit': code, 'shots': sorted(named),
          'mock_requests': {k: len(v) for k, v in reqs.items()}, 'gets': gets, 'puts': puts,
          'boundaries': 'production AICoverSettingsSection / AICoverMetaChip / AICoverEnhanceModel / AICoverCloud client + upload queue + '
                        'bundled CoverSR model (simulator Core ML = CPU) against local mock Workers; cloud image is a 4x resize stand-in'}
(out / 'status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
print(json.dumps({k: status[k] for k in ('exit', 'shots', 'mock_requests')}, ensure_ascii=False, indent=1))
print('PUTs:', [(p['path'], p['bytes'], p['type']) for p in puts])
ok = code == 0 and any('IPX-706-MISS_378x538' in p['path'] and 0 < p['bytes'] <= 3 * 1024 * 1024 for p in puts) \
     and any(g['path'].endswith('/nomos1/IPX-706_378x538.jpg') for g in gets)
print('PASS ai-ui290' if ok else 'FAIL ai-ui290'); raise SystemExit(0 if ok else 1)
