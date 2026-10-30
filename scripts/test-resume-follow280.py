#!/usr/bin/env python3
"""Build 280: 续播 (resume key/policy/book/route/line pick) + 追更提醒 (due/merge/dedupe/notifications) executed
with swiftc on macOS CI, plus source wiring contracts for players, history, detail, follow UI, BG task and LUT presets."""
from pathlib import Path
import shutil, subprocess, tempfile, sys, plistlib, re
r = Path(__file__).resolve().parents[1]
rd = lambda p: (r/p).read_text()
resume = rd('AVDB/Services/PlaybackResume.swift')
follow = rd('AVDB/Services/FollowUpdates.swift')
followUI = rd('AVDB/Views/User/FollowUpdatesView.swift')
player = rd('AVDB/Views/Player/PlayerView.swift')
pan = rd('AVDB/Views/Player/Pan115PlayerView.swift')
online = rd('AVDB/Views/Player/OnlinePlaybackPanel.swift')
detail = rd('AVDB/Views/Detail/MovieDetailView.swift')
views = rd('AVDB/Views/User/LibraryFeaturesView.swift')
user = rd('AVDB/Views/User/UserView.swift')
lists = rd('AVDB/Views/ListsView.swift')
actors = rd('AVDB/Views/Actors/ActorsView.swift')
app = rd('AVDB/AVDBApp.swift')
native = rd('AVDB/Views/Player/NativeLUT.swift')
js = rd('AVDB/Resources/OriginalLUT.js')
pbx = rd('AVDB.xcodeproj/project.pbxproj')
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())

# ---- Version / project
assert int(plist['CFBundleVersion']) >= 280
assert pbx.count(f"CURRENT_PROJECT_VERSION = {plist['CFBundleVersion']};") == 2
for f in ['PlaybackResume.swift', 'FollowUpdates.swift', 'FollowUpdatesView.swift']:
    assert pbx.count(f'/* {f} in Sources */') == 2 and pbx.count(f'path = {f};') == 1, f
assert 'org.avdb.follow.refresh' in plist['BGTaskSchedulerPermittedIdentifiers']
assert 'fetch' in plist['UIBackgroundModes'] and 'audio' in plist['UIBackgroundModes']
assert 'static let identifier = "org.avdb.follow.refresh"' in follow

# ---- Feature 1 续播 wiring
assert 'resumeKey: PlaybackResumeKey.make(number: movie.displayNumber, source: "115")' in pan
assert 'startFromBeginning: startFromBeginning' in pan and 'var startFromBeginning: Bool = false' in pan
assert 'resumeKey: PlaybackResumeKey.make(number: plan.number, source: plan.source.label)' in online
assert 'resumeKey: PlaybackResumeKey.make(number: movieID, source: "JavDB")' in player
assert 'OnlineQualityPlayer(plan: plan, historyMovie: model.historyMovie, historyArtwork: model.historyArtwork)' in online
core, ui = online.split('#if !ONLINE_CORE_TEST\nimport SwiftUI', 1)
assert 'OnlineResumeRequest' not in core and 'PlaybackResumeKey' not in core, 'core tests do not compile PlaybackResume.swift'
assert 'final class OnlineResumeRequest' in ui and 'OnlineResumeLinePolicy.pick(codes: rows.map(\\.code), number: number)' in ui
assert 'provider.discover(source, number: number' in ui and 'provider.resolve(rows[index], number: number' in ui
# Player: resume once per URL after readyToPlay, toast with 从头, 0 s never overwrites a stored position.
assert 'if resumeHandledURL != url {\n                        resumeHandledURL = url\n                        applyResume()' in player
assert 'PlaybackResumePolicy.startPosition(' in player and 'PlaybackResumePolicy.toast(' in player
assert '.accessibilityIdentifier("player.resume.toast")' in player and '.accessibilityIdentifier("player.resume.restart")' in player
save = player.split('private func saveResume(', 1)[1].split('\n    }\n', 1)[0]
assert 'resumeHandledURL == url' in save and 'hasStarted' in save and '!seekPending' in save
assert 'if force { saveResume(force: true, position: position) }' in player
assert 'if state == .paused { flushHistory(force: true) }' in player
# Detail page: auto-launch from history + resume-aware play button + manual fallback.
assert 'init(movieID: String, seed: Movie? = nil, autoLaunch: PlaybackAutoLaunch? = nil)' in detail
assert 'launchResume(autoLaunch, movie: movie)' in detail and 'autoLaunchDone = true' in detail
assert '.fullScreenCover(item: $onlineResume.plan)' in detail and 'startFromBeginning: onlineResume.startFromBeginning' in detail
assert 'startFromBeginning: pan115FromStart' in detail and 'Button("手动选择")' in detail
assert 'Label(historyResume?.title ?? "播放"' in detail and detail.count('.contextMenu { playMenu }') == 2
assert detail.count('playPrimary()') >= 2
# History: tap = 续播, long press = 续播 / 从头播放 / 查看详情 / 删除; delete clears resume keys.
assert views.count('PlaybackHistoryDestination(item: item, launch: .resume)') == 2
assert views.count('.contextMenu { PlaybackHistoryMenu(item: item, target:') == 2
menu = views.split('struct PlaybackHistoryMenu: View', 1)[1].split('\n}\n', 1)[0]
for s in ['"续播', '"从头播放"', '"查看详情"', '"删除"', 'launch: .fromStart', 'launch: .details', 'PlaybackHistoryActions.delete(item)']:
    assert s in menu, s
assert 'PlaybackResumeStore.shared.clear(number: item.number, scope: store.scope)' in views
assert 'MovieDetailView(movieID: item.movieID, seed: item.movie)' in views
assert 'MovieDetailView(movieID: item.movieID, seed: item.movie, autoLaunch: autoLaunch)' in views
assert '.modifier(PlaybackHistoryMenuDestinations())' in user, 'destination must sit outside the lazy List'
assert user.count('PlaybackHistorySection()') == 2 and user.count('FollowUpdatesSection()') == 2
# Privacy: resume entries never store URLs/headers/tokens.
entry = resume.split('struct PlaybackResumeEntry', 1)[1].split('}', 1)[0]
for bad in ['url', 'URL', 'token', 'header', 'cookie']:
    assert bad not in entry, bad

# ---- Feature 2 追更提醒 wiring
assert 'FollowBackgroundRefresh.register()' in app and 'didFinishLaunchingWithOptions' in app
assert 'FollowUpdateChecker.shared.foregroundCheck()' in app and 'FollowBackgroundRefresh.schedule()' in app
assert 'requestAuthorization(options: [.alert, .badge, .sound])' in follow and 'FollowNotifier.requestAuthorizationIfNeeded()' in follow
assert 'BGAppRefreshTaskRequest(identifier: identifier)' in follow and 'task.expirationHandler' in follow
assert 'CloudKit' not in follow.split('import Foundation', 1)[1] and 'registerForRemoteNotifications' not in follow
assert 'FollowToggleButton(kind: .series, tagID: seriesID, name: title, type: type)' in lists
assert 'FollowToggleButton(kind: .maker, tagID: makerID, name: title, type: type)' in lists
assert 'followStore.toggle(.actor, tagID: actorID, name: actor.displayName)' in actors
assert 'if appState.isLoggedIn, vm.hasFollowed != next { Task { await vm.toggleFollow() } }' in actors
assert '.badge(feed.unreadCount)' in followUI and 'struct FollowManageView' in followUI and 'struct ReleaseFeedView' in followUI
assert 'Task.sleep(nanoseconds: UInt64(FollowUpdatePolicy.requestSpacingSeconds' in follow

# ---- Feature 3 presets + hold-to-original wiring (engine behaviour is in test-native-lut.py)
for s in ['case off, natural, standard, enhanced', 'static let storageKey = "avdb.lut.preset.v1"', 'func selectPreset(', 'func holdOriginal(']:
    assert s in native, s
assert '.accessibilityIdentifier("lut.preset")' in native
assert 'setPreset' in js and 'withPresetSafety' in js and "presets:" in js
assert 'LongPressGesture(minimumDuration: 0.35)' in player and 'lut.holdOriginal(' in player
assert '.accessibilityIdentifier("player.lut.hold-original")' in player
assert player.count('UIPanGestureRecognizer(target:') == 1 and 'excludedTop: safeArea.top + 80' in player

pure = lambda s: s.split('// MARK: - Store', 1)[0]
main = r'''
// ---- resume key
assert(PlaybackResumeKey.make(number: "ipx_697", source: "MissAV") == "missav|IPX-697")
assert(PlaybackResumeKey.make(number: "ＩＰＸ－６９７", source: "MissAV") == "missav|IPX-697")
assert(PlaybackResumeKey.make(number: " ssis  001 ", source: "115") == "115|SSIS-001")
assert(PlaybackResumeKey.make(number: "", source: "115") == nil && PlaybackResumeKey.make(number: "A-1", source: nil) == nil)
assert(PlaybackResumeKey.make(number: "A-1", source: "a|b") == nil)
assert(PlaybackResumeKey.make(number: "abp-123", source: "Jable") != PlaybackResumeKey.make(number: "abp-123", source: "MissAV"))
// ---- policy: <5 s from start, >95 % from start, last 15 s from start, 从头 overrides
assert(PlaybackResumePolicy.startPosition(position: 750, length: 7200, fromBeginning: false) == 750)
assert(PlaybackResumePolicy.startPosition(position: 750, length: 7200, fromBeginning: true) == nil)
assert(PlaybackResumePolicy.startPosition(position: 3, length: 7200, fromBeginning: false) == nil)
assert(PlaybackResumePolicy.startPosition(position: 6900, length: 7200, fromBeginning: false) == nil)   // 95.8 %
assert(PlaybackResumePolicy.startPosition(position: 6800, length: 7200, fromBeginning: false) == 6800)  // 94.4 %
assert(PlaybackResumePolicy.startPosition(position: 290, length: 300, fromBeginning: false) == nil)
assert(PlaybackResumePolicy.startPosition(position: 600, length: nil, fromBeginning: false) == 600)
assert(PlaybackResumePolicy.startPosition(position: .nan, length: 100, fromBeginning: false) == nil)
assert(PlaybackResumePolicy.isCompleted(position: 6900, length: 7200) && !PlaybackResumePolicy.isCompleted(position: 100, length: 7200))
assert(PlaybackResumePolicy.toast(750) == "从 12:30 继续播放")
assert(PlaybackResumePolicy.toast(3725) == "从 1:02:05 继续播放")
assert(PlaybackResumePolicy.buttonTitle(position: 750, length: 7200, source: "MissAV") == "续播 12:30 · MissAV")
assert(PlaybackResumePolicy.buttonTitle(position: 7000, length: 7200, source: "MissAV") == nil)
// ---- book: throttle 5 s, force, seed never overwrites, cap, per-number removal
var book = PlaybackResumeBook()
let t0 = Date(timeIntervalSince1970: 1000)
assert(book.save("missav|A-1", position: 100, length: 3600, at: t0, force: false))
assert(!book.save("missav|A-1", position: 103, length: 3600, at: t0, force: false))
assert(book.save("missav|A-1", position: 103, length: 3600, at: t0, force: true))
assert(book.entry("missav|A-1")?.position == 103)
assert(!book.save("missav|A-1", position: -1, length: 3600, at: t0, force: true))
assert(book.save("missav|A-1", position: 200, length: .nan, at: t0, force: true) && book.entry("missav|A-1")?.length == 3600)
assert(!book.seed("missav|A-1", position: 50, length: 3600, at: t0))
assert(book.seed("jable|A-1", position: 50, length: 3600, at: t0) && book.entry("jable|A-1")?.position == 50)
assert(!book.seed("115|A-1", position: nil, length: nil, at: t0))
_ = book.save("115|B-2", position: 10, length: 100, at: t0, force: true)
book.removeAll(number: "a_1")
assert(book.entry("missav|A-1") == nil && book.entry("jable|A-1") == nil && book.entry("115|B-2") != nil)
var big = PlaybackResumeBook()
for i in 0..<(PlaybackResumeBook.capacity + 25) { _ = big.save("s|N-\(i)", position: 10, length: 100, at: Date(timeIntervalSince1970: Double(i)), force: true) }
assert(big.entries.count == PlaybackResumeBook.capacity && big.entry("s|N-0") == nil && big.entry("s|N-\(PlaybackResumeBook.capacity + 24)") != nil)
let json = try! JSONEncoder().encode(book.entries)
assert(PlaybackResumeBook(entries: try! JSONDecoder().decode([String: PlaybackResumeEntry].self, from: json)) == book)
// ---- history routing
assert(PlaybackHistoryRoute.route(source: "115", isTangxin: false) == .pan115)
assert(PlaybackHistoryRoute.route(source: "missav", isTangxin: false) == .online("MissAV"))
for label in ["Jable", "MissAV", "123AV", "MemoJav", "JavDay"] { assert(PlaybackHistoryRoute.route(source: label, isTangxin: false) == .online(label)) }
assert(PlaybackHistoryRoute.route(source: "JavDB", isTangxin: false) == .javdb)
assert(PlaybackHistoryRoute.route(source: "糖心", isTangxin: true) == .tangxin)
assert(PlaybackHistoryRoute.route(source: nil, isTangxin: false) == .detailsOnly)
assert(PlaybackHistoryRoute.route(source: "Unknown", isTangxin: false) == .detailsOnly)
// ---- online line re-pick by 番号 (session ids differ every time)
assert(OnlineResumeLinePolicy.pick(codes: ["IPX-698", "ipx-697-uncensored-leak", "ipx_697"], number: "IPX-697") == 2)
assert(OnlineResumeLinePolicy.pick(codes: ["IPX-698"], number: "IPX-697") == nil)
assert(OnlineResumeLinePolicy.pick(codes: [], number: "") == nil)

// ---- follow policy
func target(_ id: String, _ last: Double?, baselined: Bool = true, known: [String] = []) -> FollowTarget {
    FollowTarget(kind: .actor, tagID: id, name: "N" + id, type: "0", addedAt: Date(timeIntervalSince1970: 0),
                 lastChecked: last.map { Date(timeIntervalSince1970: $0) }, baselined: baselined, knownIDs: known)
}
let now = Date(timeIntervalSince1970: 100_000)
let ts = [target("a", 99_000), target("b", nil), target("c", 50_000), target("d", 70_000)]
assert(FollowUpdatePolicy.due(ts, now: now, reason: .foreground).map(\.tagID) == ["b", "c", "d"])  // a checked 1000 s ago
assert(FollowUpdatePolicy.due(ts, now: now, reason: .manual).map(\.tagID) == ["b", "c", "d", "a"])
var many: [FollowTarget] = []; for i in 0..<50 { many.append(target("t\(i)", nil)) }
assert(FollowUpdatePolicy.due(many, now: now, reason: .background).count == 8)
assert(FollowUpdatePolicy.due(many, now: now, reason: .foreground).count == 20)
assert(FollowUpdatePolicy.shouldRunForeground(lastRun: nil, now: now))
assert(!FollowUpdatePolicy.shouldRunForeground(lastRun: now.addingTimeInterval(-60), now: now))
assert(FollowUpdatePolicy.shouldRunForeground(lastRun: now.addingTimeInterval(-901), now: now))
assert(FollowTarget.makeID(.series, tagID: "9", type: "1") == "series:1:9")
func mv(_ id: String) -> FollowFetchedMovie { FollowFetchedMovie(id: id, number: id.uppercased(), title: "t" + id) }
// first check = baseline only
let (b1, f1) = FollowUpdatePolicy.merge(target("x", nil, baselined: false), fetched: [mv("m3"), mv("m2"), mv("m1")], now: now)
assert(f1.isEmpty && b1.baselined && b1.knownIDs == ["m3", "m2", "m1"] && b1.lastChecked == now)
let (b2, f2) = FollowUpdatePolicy.merge(b1, fetched: [mv("m5"), mv("m4"), mv("m4"), mv("m3"), mv("m2")], now: now)
assert(f2.map(\.id) == ["m5", "m4"] && b2.knownIDs == ["m5", "m4", "m3", "m2", "m1"])
let (_, f3) = FollowUpdatePolicy.merge(b2, fetched: [mv("m5"), mv("m4")], now: now)
assert(f3.isEmpty)
var long = b2; long.knownIDs = (0..<200).map { "k\($0)" }
let (b4, _) = FollowUpdatePolicy.merge(long, fetched: [mv("new")], now: now)
assert(b4.knownIDs.count == FollowUpdatePolicy.knownCap && b4.knownIDs.first == "new")
// feed dedupe across follows (actor + series surface the same movie once)
func fi(_ id: String, _ who: String, _ t: Double) -> ReleaseFeedItem {
    ReleaseFeedItem(movieID: id, number: id.uppercased(), title: "t", coverURL: nil, releaseDate: nil, followID: who, followName: who, kind: .actor, foundAt: Date(timeIntervalSince1970: t))
}
let r1 = FollowUpdatePolicy.insert([fi("m1", "A", 1), fi("m2", "A", 1)], into: [])
assert(r1.inserted.count == 2)
let r2 = FollowUpdatePolicy.insert([fi("m2", "S", 2), fi("m3", "S", 2), fi("m3", "A", 2)], into: r1.feed)
assert(r2.inserted.map(\.movieID) == ["m3"] && r2.feed.count == 3 && r2.feed.first?.movieID == "m3")
var huge: [ReleaseFeedItem] = []; for i in 0..<400 { huge.append(fi("h\(i)", "A", Double(i))) }
assert(FollowUpdatePolicy.insert(huge, into: []).feed.count == FollowUpdatePolicy.feedCap)
// notifications: ≤3 individual with per-movie id, otherwise one summary
let n2 = FollowUpdatePolicy.notifications(for: [fi("m1", "三上", 1), fi("m2", "三上", 1)])
assert(n2.count == 2 && n2[0].identifier == "avdb.follow.m1" && n2[0].title == "三上 有新作" && n2[0].body == "M1 t")
let n5 = FollowUpdatePolicy.notifications(for: (1...5).map { fi("m\($0)", $0 % 2 == 0 ? "A" : "B", 1) })
assert(n5.count == 1 && n5[0].title == "关注更新 5 部" && n5[0].body.hasPrefix("B、A："))
assert(FollowUpdatePolicy.notifications(for: []).isEmpty)
let codec = try! JSONDecoder().decode([FollowTarget].self, from: try! JSONEncoder().encode(ts))
assert(codec == ts)
print("PASS resume-follow280 Swift: resume key/policy(5 s, 95 %, tail)/toast/book throttle+seed+cap+per-number delete/route/line re-pick; follow due/caps/baseline/merge/dedupe/feed cap/notification plan")
'''
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as td:
        src = Path(td)/'main.swift'; binary = Path(td)/'rf280'
        src.write_text(pure(resume) + '\n' + pure(follow).replace('import Foundation', '') + main)
        subprocess.run(['swiftc', '-Onone', str(src), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
elif sys.platform == 'darwin':
    raise RuntimeError('swiftc mandatory on macOS CI')
else:
    print('SKIP Swift execution on local Linux; executed in macOS CI release job')
print('PASS resume-follow280 wiring: 115/online/JavDB resume keys, history tap=续播 + menu, detail resume button, follow UI/BG/notifications, LUT preset/hold, version 280')
