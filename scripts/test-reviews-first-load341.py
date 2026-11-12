#!/usr/bin/env python3
"""Build 341 reviews first load. Contracts: a failed first reviews load can
no longer masquerade as "no comments". The chain being fixed: movieReviews
was the last detail endpoint still calling client.get without a token and
without an isSuccess guard, so an error envelope (success=0) silently
became an empty list; ReviewsListViewModel.fetch then swallowed every
error, leaving reviews empty with no record of the failure; the panel
rendered 「暂无评论」 whenever the list was empty and not loading — even
when the header said 评论 8 — and the first load fired exactly once, so
the only retry in the UI was toggling the sort picker. Now: the endpoint
throws on error envelopes like its siblings (327/335 house pattern), the
view model records replace-load failures in loadFailed (cleared by any
successful fetch, including a genuinely empty one), expanding the panel
retries a failed first load once, and the empty state shows a retry row
on failure while 「暂无评论」 remains for the success-empty case. Static
source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '342' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 342;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 342' in wf and 'feat/reviews-first-load-341' in wf
assert 'feat/session-revalidate-340' in wf and 'feat/detail-glass-clear-339' in wf
assert wf.count('python3 scripts/test-reviews-first-load341.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-session-revalidate340.py') == 5  # the 340 gate keeps its 5 run lines
assert 'scripts/package-lut342.py' in wf and 'AVDB-342-release' in wf and 'AVDB-340-release' not in wf
pkg = (r/'scripts/package-lut342.py').read_text()
assert "=='342'" in pkg and 'AVDB-unsigned-1.0.2-342-reviews-panel-pending.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  reviews-first-load-341:' in wf and '  session-revalidate-340:' in wf

doc = (r/'Build341-ReviewsFirstLoad.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '341' in doc
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


sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
view = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()

# --- 1. The endpoint throws on error envelopes, like its siblings ---
reviews_fn = func_body(sdk, 'func movieReviews(')
assert 'useToken: true' in reviews_fn
assert 'guard resp.isSuccess else' in reviews_fn and 'throw JavDBError.apiError' in reviews_fn
assert reviews_fn.index('guard resp.isSuccess') < reviews_fn.index('return resp.data?.reviews')
# The detail view model's own loadReviews caller still tolerates throws via try?.
assert 'try? await sdk.movieReviews(movieID)' in view

# --- 2. The view model records replace-load failure; success clears it ---
vm = func_body(view, 'final class ReviewsListViewModel')
assert '@Published private(set) var loadFailed = false' in vm
fetch = func_body(vm, 'private func fetch(movieID: String, replace: Bool)')
success_part, catch_part = fetch.split('} catch {', 1)
assert 'loadFailed = false' in success_part  # any successful fetch clears, incl. genuinely empty
assert 'if replace' in catch_part and 'loadFailed = true' in catch_part  # only replace failures set it
load = func_body(vm, 'func load(movieID: String, force: Bool = false)')
assert 'if !force, isLoading { return }' in load  # no second concurrent fetch from a plain load
assert 'if !force, !reviews.isEmpty { return }' in load  # retry after failure stays possible (list is empty)

# --- 3. The panel self-heals on visibility and its empty state is honest ---
panel = func_body(view, 'struct DraggableReviewsPanel')
assert '.onChange(of: isContentVisible)' in panel
assert 'vm.loadFailed' in panel and 'vm.reviews.isEmpty' in panel and '!vm.isLoading' in panel
assert 'await vm.load(movieID: movieID)' in panel  # plain load: retries only the failed/empty state
reviews_list = func_body(panel, 'private var reviewsList: some View')
# Build 342 form: the empty state is three derived branches; the retry
# branch (this build's contract) is driven by the panel's failure
# predicate below. The two-branch `if vm.loadFailed` shape is gone.
assert 'if showReviewsRetry' in reviews_list
assert 'vm.loadFailed && !vm.isLoading' in panel
assert '评论加载失败' in reviews_list and '重试' in reviews_list
assert 'load(movieID: movieID, force: true)' in reviews_list  # the retry row force-reloads
assert '暂无评论' in reviews_list  # success-empty case unchanged
# The sort picker workaround path is intact (now redundant, still harmless).
sort_section = func_body(panel, 'private var sortSection: some View')
assert '.onChange(of: vm.sortBy)' in sort_section and 'load(movieID: movieID, force: true)' in sort_section

print('PASS test-reviews-first-load341: reviews endpoint throws on error '
      'envelopes, the view model records replace-load failures, the panel '
      'retries a failed first load on expansion and shows a retry row '
      'instead of a fake 「暂无评论」, release 342')
