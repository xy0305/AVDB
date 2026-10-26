"""Source guards for build 262. Swift execution is a separate macOS step.
No network and no adult media.
"""
from pathlib import Path
import os, plistlib
R = Path(__file__).resolve().parents[1]
for name in ['ONLINE254_LIVE', 'SUBTITLE_LIVE_PROBE', 'JAVBUS_LIVE_PROBE']:
    assert os.environ.get(name) not in ('1', 'true'), 'Live probe flag forbidden: ' + name
detail = (R / 'AVDB/Views/Detail/MovieDetailView.swift').read_text()
cards = (R / 'AVDB/Views/Detail/PlaybackResourceCards.swift').read_text()
panel = (R / 'AVDB/Views/Player/OnlinePlaybackPanel.swift').read_text()
player = (R / 'AVDB/Views/Player/PlayerView.swift').read_text()
core = (R / 'AVDB/Services/OnlinePlaybackCore.swift').read_text()
adapters = (R / 'AVDB/Services/DetailOnlineAdapters.swift').read_text()
assert 'PlaybackResourceActions(' not in detail
assert 'PlaybackResourceCards(state: resourceCards' in detail
assert 'resourceCards.model = OnlinePlaybackModel()' in detail
assert '@StateObject private var onlinePlaybackModel' not in detail
assert 'ViewThatFits' not in cards
assert '.equatable()' in cards
assert 'query(' not in cards
assert '播放资源:' in cards and 'detail.card.online' in cards and 'detail.card.115' in cards
assert 'qualityTick % 4 == 0' in player
assert 'if appliedQuality != choice' in player
assert 'struct PlaybackResourceActions' in panel
assert 'static func documentHeaders' in core
assert 'error is OnlineFailure' in core
assert adapters.count('OnlinePolicy.documentHeaders') == 2
assert 'OnlinePolicy.headers(referrer: referrer)' in core  # media validation unchanged
info = plistlib.loads((R / 'AVDB/Resources/Info.plist').read_bytes())
project = (R / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert info['CFBundleShortVersionString'] == '1.0.2'
assert info['CFBundleVersion'] == '262'
assert project.count('CURRENT_PROJECT_VERSION = 262;') == 2
assert project.count('MARKETING_VERSION = 1.0.2;') == 2
assert project.count('IPHONEOS_DEPLOYMENT_TARGET = 17.0;') >= 2
print('PASS262 source: lazy model, stable cards, document headers, stage-preserving transport')
