#!/usr/bin/env python3
"""315: 中指通月度精選 — months recovered from on-screen OCR of the monthly videos."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '337' and pbx.count('CURRENT_PROJECT_VERSION = 337;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
ocr = [m for m in data['months'] if m['source_type'] == 'video_ocr']
assert len(ocr) >= 8, len(ocr)
for ym in ['2020-07', '2020-08', '2020-09', '2020-11', '2020-12', '2021-05', '2021-08', '2021-11']:
    assert months[ym]['source_type'] == 'video_ocr', ym
for m in ocr:
    assert m['source'] == m['video'] and m['video'].startswith('https://www.youtube.com/watch?v='), m['month']
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 31 and total >= 740, (len(months), total)
view = (r/'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift').read_text()
assert 'case "video_ocr"' in view
print(f'PASS zzt315: {len(months)} months, {total} codes, {len(ocr)} OCR months', flush=True)
