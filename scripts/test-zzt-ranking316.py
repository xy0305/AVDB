#!/usr/bin/env python3
"""316: 中指通月度精選 — more months recovered from on-screen/subtitle OCR."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '347' and pbx.count('CURRENT_PROJECT_VERSION = 347;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
for ym in ['2020-03', '2020-05', '2020-10', '2021-01']:
    assert months[ym]['source_type'] == 'video_ocr' and len(months[ym]['entries']) >= 8, ym
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 35 and total >= 810, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt316: {len(months)} months, {total} codes', flush=True)
