#!/usr/bin/env python3
"""Build 308 — ONE tab: native port of the one-rex.js widget protocol as a 7th bottom tab."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '308' and pbx.count('CURRENT_PROJECT_VERSION = 308;') == 2

# Bottom tab wiring: .one sits between tangxin and me, titled ONE.
chrome = (r / 'AVDB/Views/TabBarChrome.swift').read_text()
tab_enum = chrome.split('enum AppTab', 1)[1].split('var id', 1)[0]
assert 'case home, rankings, categories, actors, tangxin, one, me' in tab_enum
assert 'case .one: return "ONE"' in chrome
assert 'case .one: return "play.circle"' in chrome
content = (r / 'AVDB/Views/ContentView.swift').read_text()
assert 'case .one: OneRootView()' in content

# New files registered in the project (file refs + build files).
assert pbx.count('OneCore.swift') >= 3 and pbx.count('OneView.swift') >= 3
assert 'OneCore.swift in Sources' in pbx and 'OneView.swift in Sources' in pbx

core = (r / 'AVDB/Services/OneCore.swift').read_text()
# Protocol constants from the script: old-protocol version (full MP4 in video_download),
# seed API hosts, guest bootstrap, encrypted transport + MD5 signing.
assert '"1.6.0"' in core and 'api.2b37894.com' in core and '"bootstrap"' in core
assert 'article/discovery' in core and 'article/search' in core and 'article/detail' in core
assert 'video_download' in core and 'isPreviewOnly' in core
assert 'kCCAlgorithmAES' in core and 'Insecure.MD5' in core
assert 'flutter_img' in core and 'flutter_video_download' in core
# Sections exactly as the widget defines them, plus the local region classifier.
for token in ['case newest, hot, jp, cn, us, live', 'OneClassifier', 'monthFeed', 'hotMonth', 'TangxinPolicy.permitted']:
    assert token in core, token

view = (r / 'AVDB/Views/OneView.swift').read_text()
for token in ['struct OneRootView', 'struct OneSearchView', 'struct OneDetailView', 'OneSection.allCases',
              'KSChromePlayer', 'progressID: "one:', 'historySource: "ONE"', 'HidesFloatingTabBar']:
    assert token in view, token

# Playback history: ONE entries reopen the ONE detail, never a JavDB detail.
stores = (r / 'AVDB/Services/FeatureStores.swift').read_text()
assert 'onePrefix = "one:"' in stores and 'var isOne' in stores
resume = (r / 'AVDB/Services/PlaybackResume.swift').read_text()
assert 'case pan115, online(String), javdb, tangxin, one, detailsOnly' in resume
library = (r / 'AVDB/Views/User/LibraryFeaturesView.swift').read_text()
assert 'OneHistoryDestinations' in library and 'OneDetailView(seed: OneArticle.stub' in library

# Release wiring.
workflow = (r / '.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 308' in workflow
assert 'python3 scripts/test-one308.py;' in workflow
assert 'scripts/package-lut308.py' in workflow and 'AVDB-308-release' in workflow
package = (r / 'scripts/package-lut308.py').read_text()
assert "=='308'" in package and 'AVDB-unsigned-1.0.2-308-one-tab.ipa' in package

print('PASS one308: ONE is the 7th bottom tab; native protocol port (bootstrap/discovery/search/detail, '
      'AES+MD5, month-scan partitions, full-MP4 lines), history route, build 308')
