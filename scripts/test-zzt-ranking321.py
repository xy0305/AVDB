#!/usr/bin/env python3
"""321: 中指通月度精選 — remaining age-gated months from browser-copied YouTube comments."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '329' and pbx.count('CURRENT_PROJECT_VERSION = 329;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
added = ['2019-09','2019-11','2019-12','2020-06','2021-02','2021-03','2021-04','2021-06','2021-07','2021-10','2022-04','2022-05']
for ym in added:
    assert months[ym]['source_type'] == 'youtube_comments' and len(months[ym]['entries']) >= 8, (ym, months.get(ym))
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 79 and total >= 1780, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt321: {len(months)} months, {total} codes', flush=True)
