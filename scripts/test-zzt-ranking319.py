#!/usr/bin/env python3
"""319: 中指通月度精選 — 2023-09..12, 2022-01/12, 2025-11 from YouTube original OCR."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '320' and pbx.count('CURRENT_PROJECT_VERSION = 320;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
added = ['2023-09','2023-10','2023-11','2023-12','2022-01','2022-12','2025-11']
for ym in added:
    assert months[ym]['source_type'] == 'video_ocr' and len(months[ym]['entries']) >= 15, (ym, months.get(ym))
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 60 and total >= 1390, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt319: {len(months)} months, {total} codes', flush=True)
