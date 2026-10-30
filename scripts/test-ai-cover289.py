#!/usr/bin/env python3
"""Build 289 — AI image enhancement (cover upscaler, 4xNomosWebPhoto) is ALWAYS allowed regardless of thermal state,
in both 自动 and 手动. Thermal throttling applies only to live subtitles. Static check + compiled Swift check of the
shipping AICoverPolicy.swift at every thermal level."""
import os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
policy = (r / 'AVDB/Services/AICoverPolicy.swift').read_text()
enh = (r / 'AVDB/Services/AICoverEnhancer.swift').read_text()
code = lambda s: '\n'.join(l.split('//')[0] for l in s.splitlines())
for name, src in [('AICoverPolicy.swift', policy), ('AICoverEnhancer.swift', enh)]:
    assert not re.search(r'thermal', code(src), re.I), f'{name} still reads/gates on thermal state'
assert '设备温度较高' not in policy and 'case .hot' not in policy and ', hot,' not in policy
for f in (r / 'AVDB').rglob('AICover*.swift'):
    assert 'thermalState' not in f.read_text(), f
# Live subtitles keep their thermal throttle
assert 'thermalState' in (r / 'AVDB/Services/LiveSubtitleEngine.swift').read_text() or 'thermalState' in (r / 'AVDB/Services/LiveSubtitleCore.swift').read_text()
swiftc = shutil.which('swiftc') or ('/workspace/swift/usr/bin/swiftc' if os.path.exists('/workspace/swift/usr/bin/swiftc') else None)
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift (no swiftc)')
else:
    main = '''
var fails = 0
func check(_ c: Bool, _ m: String) { if !c { fails += 1; print("FAIL", m) } }
for manual in [false, true] {
    // The guard has no thermal input at all; every thermal level (nominal…critical) maps to the same verdict.
    check(AICoverEnhanceGuard.verdict(manual: manual, lowPower: false, battery: 0.9, charging: false) == .ok, "cool/hot device ok manual=\\(manual)")
    check(AICoverEnhanceGuard.verdict(manual: manual, lowPower: false, battery: -1, charging: false) == .ok, "unknown battery ok manual=\\(manual)")
}
check(AICoverEnhanceGuard.verdict(manual: true, lowPower: true, battery: 0.05, charging: false) == .ok, "manual always runs")
if fails > 0 { fatalError("\\(fails) failures") }
print("PASS ai-cover289 swift: enhancement allowed at every thermal state (auto + manual)")
'''
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / 'AICoverPolicy.swift').write_text(policy); (Path(d) / 'main.swift').write_text(main)
        subprocess.run([swiftc, '-o', f'{d}/t', f'{d}/AICoverPolicy.swift', f'{d}/main.swift'], check=True)
        subprocess.run([f'{d}/t'], check=True)
print('PASS ai-cover289: no thermal gating for AI image enhancement (自动 + 手动); thermal throttle only in live subtitles')
