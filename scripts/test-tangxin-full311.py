#!/usr/bin/env python3
"""Build 311 — Tangxin full content: sitemap-driven author/tag indexes,
partition entry, and no title/tag keyword gate inside Tangxin.

The Tangxin module now shows the source as published (the app owner's call:
creator-chosen titles on a creator platform). TangxinPolicy.permitted is
retained only because OneCore still uses it; Tangxin itself must not call it.
"""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '341' and pbx.count('CURRENT_PROJECT_VERSION = 341;') == 2

core = (r / 'AVDB/Services/TangxinCore.swift').read_text()
# Sitemap is the live enumeration source (no hardcoded author/tag lists).
for token in ['sitemap-index.xml', 'static func sitemap(_ url: URL)', 'sitemapChildren',
              'sitemapEntries', 'func index() async throws -> TangxinIndex',
              'struct TangxinIndex']:
    assert token in core, token
# The keyword screen survives only as a helper for OneCore.
tangxin_part = core.split('struct TangxinClient')[0]
assert 'static func permitted' in core
for gated in ['TangxinPolicy.permitted((candidates', 'TangxinPolicy.permitted(name)',
              'TangxinPolicy.permitted(([title,summary]', '(p.first != "tag" || permitted']:
    assert gated not in core, gated
one = (r / 'AVDB/Services/OneCore.swift').read_text()
assert 'TangxinPolicy.permitted' in one  # ONE keeps its own screening, untouched.

view = (r / 'AVDB/Views/TangxinView.swift').read_text()
for token in ['tangxin.partition', 'TangxinIndexView', 'TangxinIndexModel',
              'tangxin.index.authors', 'tangxin.index.tags', 'Text("作者")', 'Text("标签")']:
    assert token in view, token
assert '通过内容筛查' not in view and '年龄或同意风险筛查' not in view

# Swift contract tests updated to the as-published behavior.
regression = (r / 'scripts/TangxinRegression261.swift').read_text()
for token in ['page.videos.count == 1 && page.report.blocked == 0', 'sitemapEntries',
              'sitemapChildren', 'mixed.videos.count == 2']:
    assert token in regression, token
uitests = (r / 'scripts/TangxinUITests261.swift').read_text()
assert 'XCTAssertTrue(app.buttons["tangxin.video.blocked"].waitForExistence' in uitests

# Release wiring.
workflow = (r / '.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 341' in workflow
assert 'python3 scripts/test-tangxin-full311.py;' in workflow
assert 'scripts/package-lut341.py' in workflow and 'AVDB-341-release' in workflow
package = (r / 'scripts/package-lut341.py').read_text()
assert "=='341'" in package and 'AVDB-unsigned-1.0.2-341-reviews-first-load.ipa' in package

print('PASS tangxin-full311: sitemap author/tag indexes + partitions, Tangxin keyword gate removed '
      '(permitted retained for ONE), version + release wiring at 311')
