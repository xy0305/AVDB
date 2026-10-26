from pathlib import Path
root = Path(__file__).resolve().parents[1]
detail = (root / 'AVDB/Views/Detail/MovieDetailView.swift').read_text()
cards = (root / 'AVDB/Views/Detail/PlaybackResourceCards.swift').read_text()
panel = (root / 'AVDB/Views/Player/OnlinePlaybackPanel.swift').read_text()
assert 'PlaybackResourceActions(' not in detail
assert 'detail.resource.115' not in detail and 'detail.resource.online' not in detail
assert 'PlaybackResourceCards(' in detail
assert 'play115 = true' in detail and 'showOnlinePlayback = true' in detail
assert 'Pan115PlayerView(movie: movie' in detail
assert 'OnlinePlaybackSheet(' in detail
assert '播放资源:' in cards and '115 原画' in cards and '选择播放文件' in cards
assert '打开 115 匹配资源' in cards and '需先在「我的」配置 115' in cards
assert '在线播放' in cards and 'detail.card.online' in cards and 'detail.card.115' in cards
assert 'query(' not in cards
assert 'struct PlaybackResourceActions' in panel and 'struct OnlinePlaybackSheet' in panel
assert 'CURRENT_PROJECT_VERSION = 262;' in (root / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert '<string>262</string>' in (root / 'AVDB/Resources/Info.plist').read_text()
print('PASS260 layout source: restored resource row, peer online card, no auto query, 115 callback retained')
