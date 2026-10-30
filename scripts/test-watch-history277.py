#!/usr/bin/env python3
"""Build 277 「观看历史」: store policy execution (record/dedupe/cap/progress/delete/persistence/legacy decode)
plus wiring guards for every player entry point and the 我的 UI."""
from pathlib import Path
import shutil, subprocess, tempfile, sys, plistlib
r = Path(__file__).resolve().parents[1]
stores = (r/'AVDB/Services/FeatureStores.swift').read_text()
player = (r/'AVDB/Views/Player/PlayerView.swift').read_text()
pan = (r/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
online = (r/'AVDB/Views/Player/OnlinePlaybackPanel.swift').read_text()
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
tangxin = (r/'AVDB/Views/TangxinView.swift').read_text()
views = (r/'AVDB/Views/User/LibraryFeaturesView.swift').read_text()
user = (r/'AVDB/Views/User/UserView.swift').read_text()

# Entry points: catalog, 115, online (MissAV/Jable/123AV/MemoJav/JavDay), 糖心.
assert 'historyMovie: vm.historyMovie,' in player and 'historySource: "JavDB"' in player
assert 'historyArtwork: historyArtwork,' in pan and 'historySource: "115"' in pan
assert 'OnlineQualityPlayer(plan: plan, historyMovie: model.historyMovie, historyArtwork: model.historyArtwork)' in online
assert 'historySource: plan.source.label' in online
assert '#if !ONLINE_CORE_TEST\n    /// 观看历史' in online, 'core-test builds must not see Movie/UIImage'
assert 'onlinePlaybackModel.historyMovie = movie' in detail
assert 'historySource:"糖心",historyPage:video.url' in tangxin
# Progress: gated start, periodic + pause/end/exit/background flush, same account/scope.
assert 'historyRecordedID = movie.id' in player
assert 'if state == .paused { flushHistory(force: true) }' in player
assert 'state == .playedToTheEnd { flushHistory(force: true' in player
assert 'UIApplication.willResignActiveNotification)) { _ in\n            flushHistory(force: true)' in player
assert '.onDisappear {\n            flushHistory(force: true)' in player
flush = player.split('private func flushHistory(', 1)[1].split('\n    }\n', 1)[0]
assert 'guard let id = historyRecordedID, APIClient.shared.token == historyToken' in flush
assert 'scope: historyScope' in flush
# UI.
assert 'PlaybackHistorySection()' in user and user.count('PlaybackHistorySection()') == 2
assert '.modifier(TangxinHistoryDestinations())' in user
assert 'Label("播放历史"' not in user
for s in ['ScrollView(.horizontal)', 'Label("观看历史"', '全部', 'PlaybackHistoryProgressBar',
          'PlaybackHistoryFormat.relative(item.playedAt)', 'store.remove(item.id)', 'store.clear()', 'confirmationDialog(',
          'ContentUnavailableView("还没有观看历史"', 'MoviePosterImage(movie: item.movie', 'ClippedAspectFill(aspectRatio: 0.7',
          'MovieDetailView(movieID: item.movieID, seed: item.movie)', 'TangxinDetailView(video: TangxinVideo(']:
    assert s in views, s
# Schema privacy: no stream/headers/tokens in the persisted item.
schema = stores.split('struct PlaybackHistoryItem:', 1)[1].split('struct PlaybackHistoryList', 1)[0]
for forbidden in ['token', 'streamURL', 'headers', 'magnetURL', 'playURL', 'cookie']:
    assert forbidden not in schema, forbidden
assert 'static let capacity = 500' in stores
assert 'accountID.map { "user-\\($0)" } ?? Self.guestScope' in stores
assert plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion'] == '282'

policy = 'struct PlaybackHistoryItem:' + stores.split('struct PlaybackHistoryItem:', 1)[1].split('@MainActor\nfinal class PlaybackHistoryStore', 1)[0]
main = r'''
struct Movie { init(id: String, type: String? = nil, number: String? = nil, title: String? = nil, thumbURL: String? = nil, coverURL: String? = nil) {} }
func item(_ id: String, _ t: Double) -> PlaybackHistoryItem {
    PlaybackHistoryItem(movieID: id, number: id.uppercased(), title: "测试 " + id, type: nil, coverURL: nil, playedAt: Date(timeIntervalSince1970: t))
}
var list = PlaybackHistoryList()
list.record(item("a", 1)); list.record(item("b", 2)); list.record(item("c", 3))
assert(list.items.map(\.movieID) == ["c", "b", "a"])
// Progress: first value always written, then only ≥10 s or forced.
assert(list.updateProgress("a", position: 100, length: 3600, at: Date(timeIntervalSince1970: 4), force: false))
assert(!list.updateProgress("a", position: 105, length: 3600, at: Date(timeIntervalSince1970: 5), force: false))
assert(list.updateProgress("a", position: 106, length: 3600, at: Date(timeIntervalSince1970: 6), force: true))
assert(list.items.first { $0.movieID == "a" }?.position == 106)
assert(!list.updateProgress("missing", position: 50, length: 60, at: Date(), force: true))
assert(!list.updateProgress("a", position: .nan, length: 60, at: Date(), force: true))
// Dedupe moves to top and keeps the resume point.
list.record(item("a", 10))
assert(list.items.map(\.movieID) == ["a", "c", "b"])
assert(list.items[0].position == 106 && list.items[0].length == 3600)
assert(abs((list.items[0].fraction ?? 0) - 106.0 / 3600.0) < 1e-9)
assert(PlaybackHistoryFormat.progressText(list.items[0]) == "看到 01:46 / 1:00:00")
// Delete / clear.
list.remove("c"); assert(list.items.map(\.movieID) == ["a", "b"])
// Cap 500, newest kept, evictions reported.
var big = PlaybackHistoryList()
var evicted: [String] = []
for i in 0..<520 { evicted += big.record(item("m\(i)", Double(i))) }
assert(big.items.count == PlaybackHistoryList.capacity && big.items.count == 500)
assert(big.items.first?.movieID == "m519" && big.items.last?.movieID == "m20")
assert(evicted == (0..<20).map { "m\($0)" })
// Persistence round trip through a UserDefaults suite, sorted newest-first on load.
let suite = "avdb.history277." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(try! JSONEncoder().encode(list.items.reversed()), forKey: "k")
let restored = PlaybackHistoryList(items: try! JSONDecoder().decode([PlaybackHistoryItem].self, from: defaults.data(forKey: "k")!))
assert(restored == list)
// Legacy Build ≤276 JSON (no source/position/length/page/poster) still decodes.
let legacy = #"[{"movieID":"old","number":"OLD-001","title":"旧记录","playedAt":1000}]"#.data(using: .utf8)!
let old = try! JSONDecoder().decode([PlaybackHistoryItem].self, from: legacy)
assert(old.count == 1 && old[0].position == nil && old[0].fraction == nil && old[0].source == nil)
var cleared = restored; cleared.clear(); assert(cleared.items.isEmpty)
// Relative day labels.
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 14, minute: 0))!
assert(PlaybackHistoryFormat.relative(cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9, minute: 5))!, now: now, calendar: cal) == "今天 09:05")
assert(PlaybackHistoryFormat.relative(cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 23, minute: 30))!, now: now, calendar: cal) == "昨天 23:30")
assert(PlaybackHistoryFormat.relative(cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 1))!, now: now, calendar: cal) == "10月3日")
assert(PlaybackHistoryFormat.relative(cal.date(from: DateComponents(year: 2025, month: 12, day: 1, hour: 1))!, now: now, calendar: cal) == "2025年12月1日")
print("PASS watch-history277 Swift: record/dedupe-to-top/keep-resume/progress throttle/delete/cap 500/persistence/legacy decode/relative dates")
'''
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as td:
        source = Path(td)/'main.swift'; binary = Path(td)/'history277'
        source.write_text('import Foundation\n' + policy + main)
        subprocess.run(['swiftc', '-Onone', str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
elif sys.platform == 'darwin':
    raise RuntimeError('swiftc mandatory on macOS CI')
else:
    print('SKIP Swift execution on local Linux; executed in macOS CI release job')
print('PASS watch-history277 wiring: JavDB/115/online/糖心 entry points, progress flush, 我的 strip + 全部 grid, delete/清空, privacy schema, version 277')
