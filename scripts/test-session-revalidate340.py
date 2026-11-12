#!/usr/bin/env python3
"""Build 340 session revalidate. Contracts: a detail-page auth-class error
no longer marks the whole session rejected by itself. Since Build 335 the
detail load carries token-carrying endpoints whose auth behaviour can
differ per account — a second, lower-privilege account can draw an
auth-class reply (JWTVerificationError / 「請登錄帳號」) from a business
endpoint while its credential is perfectly valid — and the Build 327 view
hook turned that one reply into a dropped login. The profile endpoint is
the single arbiter again: the view now calls AppState.revalidateCredential(),
which makes exactly one profile attempt and only routes to the existing
needsReauth marking when the profile check itself fails authentication.
Any other failure leaves the session untouched. The 327 policy is
unchanged: markNeedsReauth retains the token, resumeValidation's 401 path
still marks, logout alone clears. Static source contracts on Linux;
behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '343' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 343;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 343' in wf and 'feat/session-revalidate-340' in wf
assert 'feat/detail-glass-clear-339' in wf and 'feat/logout-access-338' in wf
assert wf.count('python3 scripts/test-session-revalidate340.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-clear-glass339.py') == 5  # the 339 gate keeps its 5 run lines
assert 'scripts/package-lut343.py' in wf and 'AVDB-343-release' in wf and 'AVDB-339-release' not in wf
pkg = (r/'scripts/package-lut343.py').read_text()
assert "=='343'" in pkg and 'AVDB-unsigned-1.0.2-343-list-landscape-cover.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  session-revalidate-340:' in wf and '  clear-glass-339:' in wf

doc = (r/'Build340-SessionRevalidate.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '340' in doc
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


app = (r/'AVDB/AVDBApp.swift').read_text()

# --- 1. The single arbiter: one profile attempt, auth failure only marks ---
reval = func_body(app, 'func revalidateCredential()')
assert reval.count('fetchProfile()') == 1  # exactly one profile-endpoint attempt
assert 'for attempt' not in reval and 'pause(' not in reval  # no retry burst (unlike resumeValidation)
assert 'activeToken ?? readToken()' in reval  # stored-token pattern, as in markNeedsReauth
assert 'sessionStatus != .needsReauth' in reval  # already marked: 327 leaves recovery to re-login / cold launch
assert 'revalidation' in reval and 'inFlight.token == token' in reval  # dedicated in-flight guard, per token
assert 'generation = epoch' in reval and 'readToken() == token' in reval  # stale results ignored on identity change
assert reval.count('markNeedsReauth()') == 1
assert 'JavDBError.isAuthenticationFailure(error)' in reval
assert reval.index('JavDBError.isAuthenticationFailure(error)') < reval.index('markNeedsReauth()')
assert 'sessionStatus = .validated' in reval and 'currentUser = user' in reval and 'isLoggedIn = true' in reval

# --- 2. The 327 policy itself is untouched ---
mark = func_body(app, 'func markNeedsReauth()')
assert 'sessionStatus = .needsReauth' in mark and 'isLoggedIn = false' in mark
assert 'logout()' not in mark and 'setToken' not in mark  # credential retained, never cleared here
resume = func_body(app, 'func resumeValidation()')
assert 'JavDBError.httpError(401' in resume and 'sessionStatus = .needsReauth' in resume  # profile 401 still marks
logout = func_body(app, 'func logout()')
assert 'JavDBSDK.shared.logout()' in logout and 'sessionStatus = .signedOut' in logout  # only explicit logout clears

# --- 3. The view asks for revalidation; it never marks the session itself ---
view = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'appState.revalidateCredential()' in view
assert 'markNeedsReauth()' not in view
# The page's own auth-error classification and failure/retry UI are unchanged.
assert 'JavDBError.isAuthenticationFailure(error)' in view
assert 'vm.isAuthError' in view and 'detail-error-login' in view

print('PASS test-session-revalidate340: detail auth errors trigger one '
      'profile-endpoint revalidation; the session drops only when the '
      'profile check itself fails authentication, 327 policy intact, '
      'release 343')
