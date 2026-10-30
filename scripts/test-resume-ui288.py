#!/usr/bin/env python3
"""Build 288 resume-pill before/after screenshots on the widest and narrowest available iPhone simulators."""
from pathlib import Path
import json, platform, shutil, subprocess
r = Path(__file__).resolve().parents[1]; out = r / 'evidence-resume288'; out.mkdir(parents=True, exist_ok=True)
assert platform.system() == 'Darwin'
subprocess.run(['ruby', str(r / 'scripts/live288/setup-resume288.rb')], check=True, cwd=r)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
pro = next((d for d in phones if d['name'].endswith('Pro') ), phones[0])
narrow = next((d for n in ['iPhone SE', 'mini', 'iPhone 16e', 'iPhone 17e', 'iPhone 16', 'iPhone 17'] for d in phones if n in d['name'] and 'Pro' not in d['name'] and 'Plus' not in d['name'] and 'Max' not in d['name'] and 'Air' not in d['name']), None)
targets = [pro] + ([narrow] if narrow and narrow['udid'] != pro['udid'] else [])
shots = out / 'shots'; shots.mkdir(exist_ok=True)
named, codes = [], []
for dev in targets:
    if dev['state'] != 'Booted': subprocess.run(['xcrun', 'simctl', 'boot', dev['udid']], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', dev['udid'], '-b'], check=True)
    subprocess.run(['xcrun', 'simctl', 'status_bar', dev['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100'], check=False)
    tag = dev['name'].replace(' ', '_').replace('(', '').replace(')', '')
    res = out / f'Resume288-{tag}.xcresult'
    p = subprocess.run(['xcodebuild', 'test', '-project', str(out / 'Resume288.xcodeproj'), '-scheme', 'Resume288',
                        '-destination', 'platform=iOS Simulator,id=' + dev['udid'], '-derivedDataPath', str(out / 'Derived'),
                        '-resultBundlePath', str(res), 'CODE_SIGNING_ALLOWED=NO'], cwd=r, capture_output=True, text=True)
    (out / f'test-{tag}.log').write_text(p.stdout[-100000:] + p.stderr[-20000:])
    codes.append(p.returncode)
    for l in p.stdout.splitlines():
        if 'PILL288' in l: print(dev['name'], l.strip())
    raw = out / f'att-{tag}'
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(res), '--output-path', str(raw)], check=False)
    m = raw / 'manifest.json'
    if m.exists():
        for test in json.loads(m.read_text()):
            for att in test.get('attachments', []):
                src = raw / att['exportedFileName']; name = att.get('suggestedHumanReadableName') or att['exportedFileName']
                if not name[:2].isdigit() or src.suffix.lower() not in ('.png', '.jpg', '.jpeg'): continue
                dst = shots / (tag + '-' + name.split('_0_')[0].replace(' ', '_') + src.suffix); shutil.copy(src, dst); named.append(dst.name)
(out / 'status.json').write_text(json.dumps({'devices': [d['name'] for d in targets], 'exit': codes, 'shots': sorted(named)}, ensure_ascii=False, indent=2))
print(json.dumps(sorted(named), ensure_ascii=False))
raise SystemExit(max(codes) if codes else 1)
