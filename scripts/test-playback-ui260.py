from pathlib import Path
import json, subprocess, sys, platform
R = Path(__file__).resolve().parents[1]
out = R / 'evidence260'
out.mkdir(exist_ok=True)
def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)
source = (R / 'AVDB/Services/CatalogueMetadata.swift').read_text()
(out / 'Identity260.swift').write_text(
    'import Foundation\nenum CatalogueIdentity {'
    + source.split('enum CatalogueIdentity {', 1)[1].split('\nstruct ScrapedMetadata:', 1)[0]
)
assert platform.system() == 'Darwin', 'Real XCTest requires Xcode; no Linux screenshot substitutes'
run(['ruby', str(R / 'scripts/setup-playback-ui260.rb')], cwd=R)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
selected = {}
for kind in ['iPhone', 'iPad']:
    choices = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if kind in d['name']]
    assert choices, kind
    device = choices[0]
    selected[kind] = device
    if device['state'] != 'Booted':
        run(['xcrun', 'simctl', 'boot', device['udid']])
    run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'])
    result = out / (kind + '.xcresult')
    attachments = out / (kind + '-screenshots')
    attachments.mkdir(exist_ok=True)
    code = subprocess.call([
        'xcodebuild', 'test', '-project', str(out / 'Playback260.xcodeproj'), '-scheme', 'Playback260',
        '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + device['udid'],
        '-derivedDataPath', str(out / 'Derived'), '-resultBundlePath', str(result),
        '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO'
    ], cwd=R)
    if result.exists():
        run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(attachments)])
    selected[kind]['testExit'] = code
    (out / 'ui260-status.json').write_text(json.dumps(selected, indent=2))
    if code:
        sys.exit(code)
print('PASS260 restored resource cards and inert online sheet: iPhone + iPad; no site or media access')
