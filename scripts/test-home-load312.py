#!/usr/bin/env python3
"""312: static production wiring + executable async loader/disk-cache tests."""
from pathlib import Path
import plistlib, shutil, subprocess, tempfile
r = Path(__file__).resolve().parents[1]
home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
loader = r/'AVDB/Services/HomeListLoading.swift'
s = loader.read_text()
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion'] == '328'
assert pbx.count('CURRENT_PROJECT_VERSION = 328;') == 2
assert pbx.count('HomeListLoading.swift in Sources') == 2
initial = home.split('    func initialLoad() async {')[1].split('    private var cacheAccountID:')[0]
assert 'withTaskGroup' in initial and 'for section in Section.allCases' in initial
assert 'async let rec' not in initial and 'await rec' not in initial
assert 'recommendedLoader.cancel(clear: changedContext)' in initial
assert 'loadGeneration == generation' in home and 'self.cacheContext == scope' in home
assert 'magnets = latest' not in home
for prop in ['recommendedState', 'latestState', 'magnetsState']:
    assert 'homeListStatus(vm.' + prop in home
assert 'case .failed:' in home and 'Button("重試", action: retry)' in home
assert 'case .empty:' in home and 'Text("暫無內容")' in home
assert 'withTaskCancellationHandler' in s and 'ticket == generation' in s
assert 'options: .atomic' in s and 'snapshot.key == key' in s
assert 'snapshot.version == 1' in s and 'dropFirst(24)' in s
assert 'accountID: cacheAccountID' in home
assert 'if !movies.isEmpty, movies != previous { self.startHQPrefetch(movies, section:' in home
# The original URL strings are serialized untouched; no thumbnail/downsample policy edits.
assert 'thumb_url = movie.thumbURL' in home and 'cover_url = movie.coverURL' in home
assert 'new_magnets = movie.hasNewMagnets' in home and 'score = movie.score' in home
print('PASS home312 production wiring and list-only cache contracts', flush=True)
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory(prefix='home312-') as d:
        exe = str(Path(d)/'HomeListLoadingTests312')
        subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(loader),
                        str(r/'scripts/HomeListLoadingTests312.swift'), '-o', exe], check=True)
        subprocess.run([exe], check=True, timeout=45)
else:
    print('SKIP executable Swift tests: swiftc unavailable; required on macOS CI')
