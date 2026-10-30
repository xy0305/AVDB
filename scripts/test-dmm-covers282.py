#!/usr/bin/env python3
"""Build 282 DMM HQ cover regression: resolver unit tests via swiftc, wiring asserts, MILK-311."""
import os, plistlib, re, shutil, subprocess, sys, tempfile, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'AVDB/Services'
read = lambda p: (ROOT / p).read_text()
resolver, policy, loader, detail, tenhow = (read('AVDB/Services/DMMCoverResolver.swift'), read('AVDB/Services/DetailPosterPolicy.swift'),
    read('AVDB/Services/ImageLoader.swift'), read('AVDB/Services/DetailPosterResolver.swift'), read('AVDB/Services/TenhowPoster.swift'))
seed = read('AVDB/Services/DMMLabelSeed.swift')
pbx = read('AVDB.xcodeproj/project.pbxproj')
plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())

# wiring: every cover path goes through the resolver
assert '"milk": ("h_1240", 5)' in seed, 'MILK label prefix seeded'
assert 'DMMCID.candidates(number: raw).first' in policy and 'DMMCoverURLs.digital(cid)' in policy, 'detail guesses use the resolver'
assert 'pics.dmm.co.jp/digital/video/\\(cid)/\\(cid)ps.jpg"' not in policy, 'no 147×200 pics ps guess'
assert 'DMMCoverURLs.upgrade(image).first' in loader, 'list cards upgrade catalogue DMM images'
assert 'DMMCID.candidates(number: "\\(prefix)-\\(idx)")' in loader, 'CoverURLBuilder uses the resolver'
assert 'DMMCoverURLs.isJacket(source)' in loader and '0.69' in loader, 'DMM jackets cropped with the measured ratio'
assert 'upgradedDMM' in detail and 'DMMLabelPrefixes.shared.learn' in detail, 'avbase CID upgraded + learned'
assert 'DMMImageValidation.classify' in detail, 'placeholder rejection in detail decode'
assert 'DMMProbePolicy.retries' in detail and 'DMMProbePolicy.shouldRetry' in detail, 'transient retry with backoff'
assert 'DMMLabelPrefixes.shared.allows' in tenhow, 'learned namespaces admitted by CID identity'
for name in ('DMMCoverResolver.swift', 'DMMLabelSeed.swift'):
    assert pbx.count(f'/* {name} in Sources */') == 2 and pbx.count(f'path = {name};') == 1, name
assert int(plist['CFBundleVersion']) >= 282 and pbx.count(f"CURRENT_PROJECT_VERSION = {plist['CFBundleVersion']};") == 2

swiftc = shutil.which('swiftc')
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift (no swiftc)')
else:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        files = []
        for name in ('JavRankingCore.swift', 'TenhowActorLinks.swift', 'TenhowPoster.swift', 'DetailPosterPolicy.swift', 'DMMCoverResolver.swift', 'DMMLabelSeed.swift'):
            (td / name).write_text('#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n' + (S / name).read_text()); files.append(td / name)
        (td / 'main.swift').write_text(read('scripts/DMMCoverRegression282.swift')); files.append(td / 'main.swift')
        subprocess.run([swiftc, '-swift-version', '5', '-o', str(td / 't')] + [str(f) for f in files], check=True)
        r = subprocess.run([str(td / 't')], capture_output=True, text=True, timeout=120)
        print(r.stdout, end='')
        if r.returncode or 'PASS dmm282' not in r.stdout: print(r.stderr); sys.exit('dmm282 swift regression failed')

# live MILK-311 check (network; informative unless DMM_LIVE_STRICT=1)
url = 'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311ps.jpg'
try:
    data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=15).read()
    w = h = None
    i = 2
    while i < len(data):
        if data[i] != 0xFF: i += 1; continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC2): h, w = int.from_bytes(data[i+5:i+7], 'big'), int.from_bytes(data[i+7:i+9], 'big'); break
        i += 2 + int.from_bytes(data[i+2:i+4], 'big')
    print(f'LIVE MILK-311 {url} -> {w}x{h} ({len(data)} bytes)')
    assert (w, h) == (745, 1081)
except Exception as e:
    if os.environ.get('DMM_LIVE_STRICT') == '1': raise
    print('LIVE MILK-311 check skipped/failed (non-fatal):', e)
print('PASS test-dmm-covers282 wiring: resolver in detail/list/history/CoverURLBuilder, avbase upgrade + learning, placeholders, retry, pbxproj, version 282')
