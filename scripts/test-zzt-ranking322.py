#!/usr/bin/env python3
"""322: 中指通月度精選 — comment verify: +98 missing, ACHJ-088→089, 2026-08 comments."""
from pathlib import Path
import json, plistlib
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '336' and pbx.count('CURRENT_PROJECT_VERSION = 336;') == 2
data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
months = {m['month']: m for m in data['months']}
m8 = months['2026-08']
assert m8['source_type'] == 'youtube_comments' and len(m8['entries']) >= 29
assert m8['source'].endswith('cqH7NrWU_AQ') or 'cqH7NrWU_AQ' in m8['video']
assert any(e['code']=='DSOD-001' for e in m8['entries'])
m9 = months['2026-09']
codes9 = {e['code'] for e in m9['entries']}
assert 'ACHJ-089' in codes9 and 'ACHJ-088' not in codes9
assert 'PRPM-002' in codes9
total = sum(len(m['entries']) for m in data['months'])
assert len(months) >= 79 and total >= 1880, (len(months), total)
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw
print(f'PASS zzt322: {len(months)} months, {total} codes', flush=True)
