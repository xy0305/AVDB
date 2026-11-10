#!/usr/bin/env python3
"""314: 中指通月度精選 history back-fill — data coverage + year-grouped month picker."""
from pathlib import Path
import json, plistlib, re
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '324' and pbx.count('CURRENT_PROJECT_VERSION = 324;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = [m['month'] for m in data['months']]
assert months == sorted(months, reverse=True) and len(set(months)) == len(months)
assert len(months) >= 23 and '2023-05' in months and '2024-12' in months, months
years = sorted({m[:4] for m in months}, reverse=True)
assert len(years) >= 3, years
total = sum(len(m['entries']) for m in data['months'])
assert total >= 600, total
for m in data['months']:
    assert m['source'] and m['source'].startswith('https://'), m['month']
    assert m['source_type'] in ('forum_list', 'youtube_transcript', 'video_title', 'video_ocr', 'youtube_comments')
    codes = [e['code'] for e in m['entries']]
    assert len(codes) == len(set(codes)), m['month']
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
view = (r/'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift').read_text()
catalog = (r/'AVDB/Services/ZhongZhiTongCatalog.swift').read_text()
assert 'struct ZZTYear' in catalog and 'var years: [ZZTYear]' in catalog and 'var monthLabel' in catalog
assert 'zzt-year-picker' in view and 'zzt-month-picker' in view and 'currentYearMonths' in view
assert view.count('.pickerStyle(.menu)') >= 2
print(f'PASS zzt314: {len(months)} months across {len(years)} years ({months[-1]}..{months[0]}), {total} codes; year/month picker wired', flush=True)
