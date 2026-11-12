#!/usr/bin/env python3
"""Build 342 reviews panel pending state. Contracts: the detail page's
draggable reviews panel can no longer show 「暂无评论」 before the first
reviews load has even started. Build 341 distinguished failure
(loadFailed) from success, but the view model had no "never loaded"
state, and the panel rendered its empty state whenever the list was
empty and not loading. The panel's only initial load trigger is the
detail view's .task, which awaits reloadDetail (plus ingest/autoLaunch
steps) before calling reviewsVM.load, while the panel becomes
interactive as soon as the movie payload lands — so expanding the panel
in that window showed a fake empty state under a header reading 评论
112, and Build 341's expansion self-heal could not rescue it because it
only fired on loadFailed. Now: the view model records hasLoadedOnce
(set by any successful fetch, never by a failure), the panel's empty
state is three mutually exclusive derived states — retry row on
failure, a pending placeholder until the first success, 「暂无评论」
only after a successful empty load — and the expansion self-heal also
fires when the first load has not succeeded yet. Static source
contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '347' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 347;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 347' in wf and 'feat/reviews-panel-pending-342' in wf
assert 'feat/reviews-first-load-341' in wf and 'feat/session-revalidate-340' in wf
assert wf.count('python3 scripts/test-reviews-panel-pending342.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-reviews-first-load341.py') == 5  # the 341 gate keeps its 5 run lines
assert 'scripts/package-lut347.py' in wf and 'AVDB-347-release' in wf and 'AVDB-341-release' not in wf
pkg = (r/'scripts/package-lut347.py').read_text()
assert "=='347'" in pkg and 'AVDB-unsigned-1.0.2-347-actor-ranking-period.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  reviews-panel-pending-342:' in wf and '  reviews-first-load-341:' in wf

doc = (r/'Build342-ReviewsPanelPending.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '342' in doc
assert 'unsigned' in doc.lower()


def func_body(src, signature):
    start = src.index(signature)
    brace = src.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    raise AssertionError('unbalanced: ' + signature)


view = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()

# --- 1. The view model records "has ever loaded successfully" ---
vm = func_body(view, 'final class ReviewsListViewModel')
assert '@Published private(set) var hasLoadedOnce = false' in vm
assert '@Published private(set) var loadFailed = false' in vm  # the 341 flag is untouched
fetch = func_body(vm, 'private func fetch(movieID: String, replace: Bool)')
success_part, catch_part = fetch.split('} catch {', 1)
assert 'hasLoadedOnce = true' in success_part  # set on success, beside the failure clear
assert 'loadFailed = false' in success_part  # 341 contract intact
assert 'hasLoadedOnce = true' not in catch_part  # a failure never marks the list as loaded

# --- 2. The panel empty state is three mutually exclusive branches ---
panel = func_body(view, 'struct DraggableReviewsPanel')
retry_pred = func_body(panel, 'private var showReviewsRetry: Bool')
assert 'vm.loadFailed && !vm.isLoading' in retry_pred  # failure, not currently reloading
pending_pred = func_body(panel, 'private var showReviewsPending: Bool')
assert '!vm.hasLoadedOnce' in pending_pred and '!showReviewsRetry' in pending_pred  # pending yields to the retry row
empty_pred = func_body(panel, 'private var showReviewsEmpty: Bool')
assert 'vm.hasLoadedOnce && !vm.loadFailed && !vm.isLoading' in empty_pred  # only after a successful empty load
reviews_list = func_body(panel, 'private var reviewsList: some View')
i_retry = reviews_list.index('if showReviewsRetry')
i_pending = reviews_list.index('else if showReviewsPending')
i_empty = reviews_list.index('else if showReviewsEmpty')
assert i_retry < i_pending < i_empty
retry_branch = reviews_list[i_retry:i_pending]
assert '评论加载失败' in retry_branch and '重试' in retry_branch  # 341 retry row unchanged
assert 'load(movieID: movieID, force: true)' in retry_branch  # and still force-reloads
pending_branch = reviews_list[i_pending:i_empty]
assert 'ProgressView()' in pending_branch and '加载中' in pending_branch  # pending placeholder, not a fake empty
assert '暂无评论' in reviews_list[i_empty:]  # genuine empty only in the last branch

# --- 3. Expanding the panel also rescues the not-yet-loaded case ---
assert '.onChange(of: isContentVisible)' in panel
assert '(vm.loadFailed || !vm.hasLoadedOnce)' in panel  # 342: widened beyond the 341 failure-only trigger
assert 'vm.reviews.isEmpty' in panel and '!vm.isLoading' in panel
assert 'await vm.load(movieID: movieID)' in panel  # plain load: fires only while the list is still unloaded/empty

print('PASS test-reviews-panel-pending342: the view model records the '
      'first successful load, the panel shows a pending placeholder '
      'instead of a fake 「暂无评论」 before it, and expansion retries '
      'a not-yet-loaded list, release 347')
