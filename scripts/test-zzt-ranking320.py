#!/usr/bin/env python3
"""320: 中指通月度精選 — 2021-09/12 + 2022-03/06/07/08/09 from YouTube comments."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '336' and pbx.count('CURRENT_PROJECT_VERSION = 336;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
added = ['2021-09','2021-12','2022-03','2022-06','2022-07','2022-08','2022-09']
for ym in added:
    assert months[ym]['source_type'] == 'youtube_comments' and len(months[ym]['entries']) >= 15, (ym, months.get(ym))
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 67 and total >= 1560, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt320: {len(months)} months, {total} codes', flush=True)
