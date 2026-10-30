#!/usr/bin/env python3
"""Build 281 simulator screenshots of the production recommender UI (seeded offline fixture)."""
from pathlib import Path
import json, os, platform, shutil, subprocess
r = Path(__file__).resolve().parents[1]; out = r / 'evidence-rec281'; out.mkdir(exist_ok=True)
assert platform.system() == 'Darwin'
subprocess.run(['ruby', str(r / 'scripts/setup-rec-ui281.rb')], check=True, cwd=r)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
if device['state'] != 'Booted': subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
subprocess.run(['xcrun', 'simctl', 'status_bar', device['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'], check=False)
code = subprocess.call(['xcodebuild', 'test', '-project', str(out / 'Rec281.xcodeproj'), '-scheme', 'Rec281',
                        '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(out / 'Derived'),
                        '-resultBundlePath', str(out / 'Rec281.xcresult'), '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO'], cwd=r)
raw = out / 'attachments'
if (out / 'Rec281.xcresult').exists():
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(out / 'Rec281.xcresult'), '--output-path', str(raw)], check=False)
shots = out / 'shots'; shots.mkdir(exist_ok=True)
named = []
manifest = raw / 'manifest.json'
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for att in test.get('attachments', []):
            src = raw / att['exportedFileName']
            name = (att.get('suggestedHumanReadableName') or att['exportedFileName'])
            base = name.split('_0_')[0].split('_')[0] if name[:2].isdigit() else name
            dst = shots / (base + src.suffix)
            shutil.copy(src, dst); named.append(dst.name)
(out / 'status.json').write_text(json.dumps({'offline': True, 'device': device, 'exit': code, 'shots': sorted(named),
    'boundaries': 'production Recommender/RecommendationStore/RecommendationsView; Movie, poster image (procedural covers), detail and JavDB source are fixtures'},
    ensure_ascii=False, indent=2))
print(json.dumps(sorted(named), ensure_ascii=False))
raise SystemExit(code)
