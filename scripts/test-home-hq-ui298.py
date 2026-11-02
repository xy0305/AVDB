#!/usr/bin/env python3
"""Build 298 simulator tests: production scheduler + hosted SwiftUI upgrade view.
Neutral generated rasters only. Not a physical-device visual acceptance."""
from pathlib import Path
import json, platform, subprocess, sys
r = Path(__file__).resolve().parents[1]
assert platform.system() == 'Darwin'
subprocess.run([sys.executable, str(r / 'scripts/test-home-hq298.py')], check=True)
subprocess.run(['ruby', str(r / 'scripts/setup-home-hq298.rb')], check=True, cwd=r)
out = r / 'evidence-homehq298'
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
code = subprocess.call(['xcodebuild', 'test', '-project', str(out / 'HomeHQ298.xcodeproj'), '-scheme', 'HomeHQ298',
                        '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(out / 'Derived'),
                        '-resultBundlePath', str(out / 'HomeHQ298.xcresult'), '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO'], cwd=r)
(out / 'status.json').write_text(json.dumps({'device': device['name'], 'exit': code, 'kind': 'ios-simulator-not-device'}, indent=2))
print('PASS home-hq-ui298' if code == 0 else 'FAIL home-hq-ui298')
raise SystemExit(code)
