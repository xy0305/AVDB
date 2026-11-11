#!/usr/bin/env python3
"""318: 中指通月度精選 — 2024-01/02 + 2023-01..04/06/07/08 from YouTube original OCR."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '337' and pbx.count('CURRENT_PROJECT_VERSION = 337;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
added = ['2024-01','2024-02','2023-01','2023-02','2023-03','2023-04','2023-06','2023-07','2023-08']
for ym in added:
    assert months[ym]['source_type'] == 'video_ocr' and len(months[ym]['entries']) >= 10, (ym, months.get(ym))
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 53 and total >= 1200, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt318: {len(months)} months, {total} codes', flush=True)
