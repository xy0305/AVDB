#!/usr/bin/env python3
"""Build 284: DMM cover for 800×538 pl-only titles (IPX-706) wins over JavDB; alternates; stale fallback refresh."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; S = ROOT / 'AVDB/Services'
read = lambda p: (ROOT / p).read_text()
resolver, loader, cachef, policy = read('AVDB/Services/DetailPosterResolver.swift'), read('AVDB/Services/ImageLoader.swift'), read('AVDB/Services/DetailPosterCache.swift'), read('AVDB/Services/DetailPosterPolicy.swift')
pbx = read('AVDB.xcodeproj/project.pbxproj'); plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())
assert 'DMMCoverURLs.fallbacks(for: url.absoluteString)' in resolver and 'downloadOne(url: next' in resolver, 'one slot tries same-image alternates'
assert 'let dmm = validated.filter { rules.contains($0)' in resolver, 'DMM rules ahead of extra JavDB sizes'
assert 'fallbackTTL' in resolver and 'provenance.label == "JavDB"' in resolver and 'cacheVersion = "dmm284"' in resolver, 'stale fallback refresh + cache version'
assert 'ttl?(value) ??' in cachef
assert 'for hq in DMMCoverURLs.upgrade(image) { append(hq) }' in loader and 'DetailPosterPolicy.candidates(number: movie.number).prefix(2)' in loader, 'list cards try DMM pl (front-cropped)'
assert 'let hq = result.prefix(2)' in loader, 'JavDB stays within the three list attempts'
assert 'officialRank' in policy
assert plist['CFBundleVersion'] == '284' and pbx.count('CURRENT_PROJECT_VERSION = 284;') == 2
swiftc = shutil.which('swiftc')
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift')
else:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td); files = []
        for name in ('JavRankingCore.swift', 'TenhowActorLinks.swift', 'TenhowPoster.swift', 'DetailPosterPolicy.swift', 'DMMCoverResolver.swift', 'DMMLabelSeed.swift', 'DetailPosterCache.swift'):
            (td / name).write_text('#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n' + (S / name).read_text()); files.append(td / name)
        (td / 'main.swift').write_text(read('scripts/DMMCoverRegression284.swift')); files.append(td / 'main.swift')
        subprocess.run([swiftc, '-swift-version', '5', '-o', str(td / 't')] + [str(f) for f in files], check=True)
        r = subprocess.run([str(td / 't')], capture_output=True, text=True, timeout=120)
        print(r.stdout, end='')
        if r.returncode or 'PASS dmm284' not in r.stdout: print(r.stderr); sys.exit('dmm284 swift regression failed')
print('PASS test-dmm-covers284 wiring: alternates in one slot, DMM-first ordering, official near-tie preference, JavDB fallback TTL, list pl crop, version 284')
