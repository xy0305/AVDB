#!/usr/bin/env python3
"""Build 294 — live subtitle reader catch-up death loop: reopen grace, soft reopen, hitch-aware jump detect."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
core = (S / 'LiveSubtitleCore.swift').read_text()
eng = (S / 'LiveSubtitleEngine.swift').read_text()
reader = (S / 'LiveAudioReader.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert pl['CFBundleVersion'] == '294' and pbx.count('CURRENT_PROJECT_VERSION = 294;') == 2
for s in ['enum LiveCatchUpPolicy', 'reopenGraceSeconds', 'softGapLimit', 'func softReopen(at',
          'static func action(playing:', 'static func isMediaJump(delta:']:
    assert s in core, s
for s in ['armCatchUpGrace', 'softRestartReader', '追帧宽限', '软追帧', '硬追帧', 'lastBigHitchAt',
          'LiveCatchUpPolicy.action', 'holdForSeek', 'seekDebounce', '450_000_000']:
    assert s in eng, s
assert 'if abs(c.time - expected) > 1.5' not in eng, '293 1.5s jump threshold must be gone'
assert 'decoded < c.time - 6, Date().timeIntervalSince(lastCatchUp) > 10' not in eng, 'bare 10s catch-up loop must be gone'
for s in ['holdForSeek', 'abortIO']:
    assert s in reader, s
wf = (r / '.github/workflows/lut4-online294.yml').read_text()
for s in ['test-live294.py', 'package-lut294.py', 'AVDB-294-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' in wf.split('jobs:')[0]
assert 'push:' not in (r / '.github/workflows/lut4-online293.yml').read_text().split('jobs:')[0], '293 must be dispatch-only'
assert (r / 'Build294-LiveSubtitle-CatchUp.md').exists()
assert "=='294'" in (r / 'scripts/package-lut294.py').read_text()
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    files = ['LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'LiveAppleTranslation.swift', 'LiveLLMTranslation.swift']
    for f in files:
        shutil.copy(S / f, d)
    shutil.copy(r / 'scripts/live294/LiveCatchUpRegression294.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5'] + files + ['main.swift', '-o', 't']
    if sys.platform == 'darwin' and Path(swiftc).name == 'swiftc':
        cmd = ['xcrun'] + cmd
    subprocess.run(cmd, cwd=d, check=True)
    out = subprocess.run([str(Path(d) / 't')], cwd=d, capture_output=True, text=True)
    print(out.stdout[-4000:])
    if out.stderr:
        print(out.stderr[-2000:], file=sys.stderr)
    assert out.returncode == 0 and 'ALL PASS 294 catch-up' in out.stdout
subprocess.run([sys.executable, str(r / 'scripts/test-live293.py')], check=True)
print('PASS live294: catch-up grace, soft/hard reopen, hitch jump guard, build 294')
