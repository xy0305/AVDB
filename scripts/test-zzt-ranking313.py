#!/usr/bin/env python3
"""313: 中指通每月作品精選 ranking source — data contract, wiring and executable Swift catalog tests."""
from pathlib import Path
import json, plistlib, re, shutil, subprocess, tempfile
r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '334' and pbx.count('CURRENT_PROJECT_VERSION = 334;') == 2
for name in ['ZhongZhiTongCatalog.swift in Sources', 'ZhongZhiTongRankingView.swift in Sources', 'ZhongZhiTongMonthly.json in Resources']:
    assert pbx.count(name) == 2, name

data = json.loads((r/'AVDB/Resources/ZhongZhiTongMonthly.json').read_text())
assert data['version'] == 1 and re.match(r'^\d{4}-\d{2}-\d{2}$', data['updated_at'])
months = [m['month'] for m in data['months']]
assert months == sorted(months, reverse=True) and len(set(months)) == len(months) and len(months) >= 12
code_re = re.compile(r'^[0-9]{0,3}[A-Z]{2,8}-[0-9]{2,6}$')
total = 0
for m in data['months']:
    assert re.match(r'^20\d{2}-(0[1-9]|1[0-2])$', m['month'])
    assert m['source_type'] in ('forum_list', 'youtube_transcript', 'video_title', 'video_ocr', 'youtube_comments')
    assert m['video'].startswith('https://www.youtube.com/watch?v=')
    assert m['entries'], m['month']
    for e in m['entries']:
        assert code_re.match(e['code']), e['code']
        assert isinstance(e['actresses'], list)
    total += len(m['entries'])
raw = json.dumps(data, ensure_ascii=False).lower()
assert 'magnet:' not in raw and 'btih' not in raw, 'no magnet links in bundled data'
assert total >= 300, total

view = (r/'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift').read_text()
rankings = (r/'AVDB/Views/Rankings/RankingsView.swift').read_text()
catalog = (r/'AVDB/Services/ZhongZhiTongCatalog.swift').read_text()
assert 'case .zhongZhiTong: ZhongZhiTongRankingView()' in rankings and 'zzt-ranking-entry' in rankings
assert 'Section("中指通")' in rankings
# Codes resolve through the existing exact-code AVDB path; no source images used as covers.
assert 'MissAVGrid(videos: videos, metadata: metadata, sourceName: "中指通"' in view
assert 'enrichMissAV: false' in view and 'image: nil' in view
assert 'zzt-month-picker' in view and '.pickerStyle(.menu)' in view
assert 'raw.githubusercontent.com/xy0305/AVDB/main/AVDB/Resources/ZhongZhiTongMonthly.json' in catalog
assert 'options: .atomic' in catalog and 'ZZTCatalog.preferred(current, remote)' in catalog
# Image pipeline untouched by this build.
for f in ['AVDB/Services/ImageLoader.swift']:
    p = r/f
    if p.exists():
        assert 'ZhongZhiTong' not in p.read_text()
print(f'PASS zzt313 data contract: {len(months)} months, {total} codes, newest {months[0]}; wiring OK', flush=True)
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory(prefix='zzt313-') as d:
        exe = str(Path(d)/'ZZTCatalogTests313')
        subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(r/'AVDB/Services/ZhongZhiTongCatalog.swift'),
                        str(r/'scripts/ZZTCatalogTests313.swift'), '-o', exe], check=True)
        subprocess.run([exe, str(r/'AVDB/Resources/ZhongZhiTongMonthly.json')], check=True, timeout=45)
else:
    print('SKIP executable Swift tests: swiftc unavailable; required on macOS CI')
