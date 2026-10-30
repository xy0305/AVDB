#!/usr/bin/env python3
"""Build 287 simulator screenshots: live subtitle overlay (portrait/landscape, 日文/中文/双语, streaming partial, zh pending), menu, settings, position edit, guard notice."""
from pathlib import Path
import json, os, platform, shutil, subprocess
r = Path(__file__).resolve().parents[1]; out = r / 'evidence-live287/ui'; out.mkdir(parents=True, exist_ok=True)
assert platform.system() == 'Darwin'
subprocess.run(['ruby', str(r / 'scripts/live287/setup-ui287.rb')], check=True, cwd=r)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
if device['state'] != 'Booted': subprocess.run(['defaults', 'write', 'com.apple.iphonesimulator', 'ConnectHardwareKeyboard', '-bool', 'false'], check=False); subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
subprocess.run(['xcrun', 'simctl', 'status_bar', device['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'], check=False)
code = subprocess.call(['xcodebuild', 'test', '-project', str(out / 'Live287.xcodeproj'), '-scheme', 'Live287',
                        '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(out / 'Derived'),
                        '-resultBundlePath', str(out / 'Live287.xcresult'), '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO'], cwd=r)
raw = out / 'attachments'
if (out / 'Live287.xcresult').exists():
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(out / 'Live287.xcresult'), '--output-path', str(raw)], check=False)
shots = out / 'shots'; shots.mkdir(exist_ok=True)
named = []
manifest = raw / 'manifest.json'
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for att in test.get('attachments', []):
            src = raw / att['exportedFileName']
            name = (att.get('suggestedHumanReadableName') or att['exportedFileName'])
            if not name[:2].isdigit() or src.suffix.lower() not in ('.png', '.jpg', '.jpeg'):
                continue          # debug descriptions / recordings stay out of the artifact
            base = name.split('_0_')[0]
            dst = shots / (base + src.suffix)
            shutil.copy(src, dst); named.append(dst.name)
(out / 'status.json').write_text(json.dumps({'offline': True, 'device': device, 'exit': code, 'shots': sorted(named),
    'boundaries': 'production LiveSubtitleOverlay/LiveOutlinedText/LiveSubtitleMenuButton/LiveSubtitleStatusChip/LiveSubtitleSettingsSheet + LiveSegmentStore.caption; engine = fixture with the production published surface; player chrome = neutral stand-in with the same 118 pt bottom reserve'},
    ensure_ascii=False, indent=2))
print(json.dumps(sorted(named), ensure_ascii=False))
raise SystemExit(code)
