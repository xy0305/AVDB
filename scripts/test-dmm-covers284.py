#!/usr/bin/env python3
"""Build 284: DMM cover for 800×538 pl-only titles (IPX-706) wins over JavDB; alternates; stale fallback refresh."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; S = ROOT / 'AVDB/Services'
read = lambda p: (ROOT / p).read_text()
resolver, loader, cachef, detail_policy = read('AVDB/Services/DetailPosterResolver.swift'), read('AVDB/Services/ImageLoader.swift'), read('AVDB/Services/DetailPosterCache.swift'), read('AVDB/Services/DetailPosterPolicy.swift')
pbx = read('AVDB.xcodeproj/project.pbxproj'); plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())
assert 'DMMCoverURLs.fallbacks(for: url.absoluteString)' in resolver and 'downloadOne(url: next' in resolver, 'one slot tries same-image alternates'
assert 'let dmm = validated.filter { rules.contains($0)' in resolver, 'DMM rules ahead of extra JavDB sizes'
assert 'fallbackTTL' in resolver and 'provenance.label == "JavDB"' in resolver and 'cacheVersion = "dmm284"' in resolver, 'stale fallback refresh + cache version'
assert 'ttl?(value) ??' in cachef
# Build 298 moved guessed full-size URLs out of the synchronous list. The safety
# invariant is the list itself, not the old splice string `let hq = result.prefix(2)`.
policy = loader.split('enum VisibleHQPosterPolicy', 1)[1].split('actor VisibleHQPosterScheduler', 1)[0]
list_fn = loader.split('public static func sources(movie: Movie)', 1)[1].split('public struct MoviePosterImage', 1)[0]
sync = list_fn.split('for source in javdb', 1)[0]
assert 'DetailPosterPolicy.candidates' not in sync, 'synchronous list does not splice guessed HQ URLs'
assert 'DMMCoverURLs.upgrade' not in sync, 'synchronous list does not splice catalogue full-size URLs'
assert 'for source in javdb { append(source) }' in list_fn, 'synchronous list keeps thumb/cover only'
assert 'return result' in list_fn and '.prefix(' not in list_fn.split('return result', 1)[0].split('func append', 1)[-1], 'synchronous list is not truncated below JavDB'
# JavDB contributes at most thumb+cover (2). A learned HQ tip may lead. Three attempts, JavDB last.
assert 'secondFallbackURL: sources.dropFirst(2).first' in loader, 'list view stops at three attempts'
assert 'FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)' in list_fn, 'JavDB is the tail of the synchronous list'
assert policy.count('return source') == 1 and 'return Array(result.prefix(1))' in policy, 'a visible card upgrades at most one already-admitted candidate'
assert 'for guess in DetailPosterPolicy.candidates(number: movie.number).prefix(2)' not in policy, 'visible upgrade does not fan out guessed full-size URLs'
for host in ('awsimgsrc.dmm.co.jp', 'pics.dmm.co.jp', 'm.media-amazon.com', 'images-na.ssl-images-amazon.com', 'www.tenhow.net', 'image.mgstage.com', 'pic.duga.jp'):
    assert host in loader, host
assert 'static let concurrency = 2' in loader and 'ListHQCoverCache.storeNegative' in loader and 'if Task.isCancelled { return nil }' in loader, 'concurrency, negative cache, and cancel contracts stay'
assert 'officialRank' in detail_policy
assert int(plist['CFBundleVersion']) >= 284 and pbx.count(f"CURRENT_PROJECT_VERSION = {plist['CFBundleVersion']};") == 2
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
