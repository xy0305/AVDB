"""Compile and run production quality selection plus AVPlayerItem application.
Injected/synthetic HLS only. Never compiles OnlineProbe255/256 or contacts a source.
"""
from pathlib import Path
import os, sys, platform, subprocess, tempfile, json
R = Path(__file__).resolve().parents[1]
for name in ['ONLINE254_LIVE', 'SUBTITLE_LIVE_PROBE', 'JAVBUS_LIVE_PROBE']:
    assert os.environ.get(name) not in ('1', 'true'), 'Live probe flag forbidden: ' + name
assert platform.system() == 'Darwin', 'Swift execution requires macOS'
def run(args, **kw):
    return subprocess.run(args, check=True, **kw)
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    identity = p / 'Identity.swift'
    s = (R / 'AVDB/Services/CatalogueMetadata.swift').read_text()
    identity.write_text('import Foundation\nenum CatalogueIdentity {' + s.split('enum CatalogueIdentity {', 1)[1].split('\nstruct ScrapedMetadata:', 1)[0])
    fixture = p / 'Fixture254.swift'
    fixture.write_text((R / 'scripts/OnlineRegression254.swift').read_text().replace('@main struct OnlineRegression254', 'struct OnlineRegression254'))
    files = [
        'AVDB/Services/PlaybackDiagnostic.swift', 'AVDB/Services/JavRankingCore.swift', 'AVDB/Services/MissAVCore.swift',
        'AVDB/Services/OnlinePlaybackCore.swift', 'AVDB/Services/OnlineAdditionalProviders.swift', 'AVDB/Services/DetailOnlineAdapters.swift',
        'AVDB/Views/Player/OnlinePlaybackPanel.swift', 'AVDB/Views/Player/PlaybackVideoMetrics.swift',
        'scripts/OnlineSafetyRegression255.swift', 'scripts/OnlineCompatibilityRegression256.swift',
        'scripts/PlaybackDiagnosticRegression257.swift', 'scripts/OnlineQualityRegression259.swift']
    common = ['-parse-as-library', '-swift-version', '5', '-D', 'ONLINE_CORE_TEST', str(identity), str(fixture), *[str(R / f) for f in files]]
    binary = p / 'neutral259-macos'
    run(['swiftc', '-target', platform.machine() + '-apple-macosx14.0', *common, '-o', str(binary)])
    run(['sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)], timeout=180)
    print('MACOS259 PASS (network denied by sandbox)', flush=True)
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
    choices = [d for runtime, ds in devices.items() if 'iOS' in runtime for d in ds if 'iPhone' in d['name']]
    assert choices, 'No iOS simulator available'
    device = choices[0]
    print('SIMULATOR259', device['name'], device['udid'], flush=True)
    if device['state'] != 'Booted':
        run(['xcrun', 'simctl', 'boot', device['udid']])
    run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'])
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    ibinary = p / 'neutral259-ios'
    run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-target', platform.machine() + '-apple-ios17.0-simulator', '-sdk', sdk, *common, '-o', str(ibinary)])
    run(['xcrun', 'simctl', 'spawn', device['udid'], str(ibinary)], timeout=180)
    print('IOS259 PASS; synthetic HLS and AVPlayerItem only; no adult source; first frame not claimed', flush=True)
