#!/usr/bin/env python3
"""Build 296 — live subtitle display: stop short-sentence pile-up (merge caps + on-screen sentence slice)."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
core = (S / 'LiveSubtitleCore.swift').read_text()
eng = (S / 'LiveSubtitleEngine.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert pl['CFBundleVersion'] == '296' and pbx.count('CURRENT_PROJECT_VERSION = 296;') == 2
for s in ['adjacentMergeMaxBody = 28', 'adjacentMergeMaxClauses = 2', 'displayMaxBody = 28',
          'static func displaySlice', 'static func sentencePieces', 'static func pickPiece']:
    assert s in core, s
assert 'adjacentMergeMaxBody = 64' not in core, '64-char merge cap must be gone'
# 295 seek/OFF fixes must remain
for s in ['enum LiveSeekPolicy', 'seekSettled', 'readerSuspended', 'modeToken', 'latencyCounter % 10']:
    assert s in core + eng, s
assert 'lead: Double = UserDefaults.standard.object(forKey: "live.subtitle.lead") as? Double ?? 20' in eng
wf = (r / '.github/workflows/lut4-online296.yml').read_text()
for s in ['test-live296.py', 'package-lut296.py', 'AVDB-296-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' in wf.split('jobs:')[0]
assert 'push:' not in (r / '.github/workflows/lut4-online295.yml').read_text().split('jobs:')[0], '295 dispatch-only'
assert 'push:' not in (r / '.github/workflows/lut4-online294.yml').read_text().split('jobs:')[0]
assert (r / 'Build296-LiveSubtitle-DisplaySplit.md').exists()
assert "=='296'" in (r / 'scripts/package-lut296.py').read_text()
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    files = ['LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'LiveAppleTranslation.swift', 'LiveLLMTranslation.swift']
    for f in files:
        shutil.copy(S / f, d)
    # Reuse 293 harness (now includes 296 merge-cap + display-slice asserts)
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
subprocess.run([sys.executable, str(r / 'scripts/test-live295.py')], check=True)
print('PASS live296: merge maxBody28/maxClauses2, display sentence slice, 295 seek/OFF kept, build 296')
