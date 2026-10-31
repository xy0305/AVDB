#!/usr/bin/env python3
"""Build 293 — whole-utterance MT (no clause-split drop) + adjacent segment merge + seek debounce / reader abort."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
prep = (S / 'LiveTranslationPrep.swift').read_text()
core = (S / 'LiveSubtitleCore.swift').read_text()
eng = (S / 'LiveSubtitleEngine.swift').read_text()
reader = (S / 'LiveAudioReader.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert pl['CFBundleVersion'] == '293' and pbx.count('CURRENT_PROJECT_VERSION = 293;') == 2
assert 'return .translate([.mt(s)])' in prep
for s in ['adjacentMergeGap', 'adjacentMergeMaxBody', 'grew ? segments[k]']:
    assert s in core, s
blob = reader + eng
for s in ['holdForSeek', 'abortIO', 'seekDebounce', '450_000_000', 'interrupted || r.abortIO', 'hasPendingSeek || hold']:
    assert s in blob, s
wf = (r / '.github/workflows/lut4-online293.yml').read_text()
for s in ['test-live293.py', 'package-lut293.py', 'AVDB-293-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' in wf.split('jobs:')[0]
assert 'push:' not in (r / '.github/workflows/lut4-online292.yml').read_text().split('jobs:')[0]
assert (r / 'THIRD_PARTY/LiveTranslation-293.md').exists()
assert "=='293'" in (r / 'scripts/package-lut293.py').read_text()
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    files = ['LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'LiveAppleTranslation.swift', 'LiveLLMTranslation.swift']
    for f in files:
        shutil.copy(S / f, d)
    shutil.copy(r / 'scripts/live293/LiveMTRegression293.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5'] + files + ['main.swift', '-o', 't']
    if sys.platform == 'darwin' and Path(swiftc).name == 'swiftc':
        cmd = ['xcrun'] + cmd
    subprocess.run(cmd, cwd=d, check=True)
    out = subprocess.run([str(Path(d) / 't')], cwd=d, capture_output=True, text=True)
    print(out.stdout[-4000:])
    if out.stderr:
        print(out.stderr[-2000:], file=sys.stderr)
    assert out.returncode == 0 and 'ALL PASS 293 translation' in out.stdout
print('PASS live293: whole-utterance MT, adjacent merge, いま/glossary, seek hold+abortIO+debounce, build 293')
