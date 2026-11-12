#!/usr/bin/env python3
"""Build 327 detail-page login token + visible auth errors. Static source
contracts on Linux; XCTest unit + UI tests run on the macOS CI job."""
from pathlib import Path
import json
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '340' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 340;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 340' in wf and 'feat/detail-auth-327' in wf
assert 'python3 scripts/test-detail-auth327.py' in wf
assert 'scripts/package-lut340.py' in wf and 'AVDB-340-release' in wf
assert 'AVDB-unsigned-1.0.2-340-session-revalidate.ipa' in (r/'scripts/package-lut340.py').read_text()
assert 'detail-auth-327' in wf
assert 'DetailAuth327Tests' in wf
assert 'test327DetailAuthErrorMessageVisible' in wf
assert 'test327DetailAuthLoginButtonPresence' in wf
# 326 hero screenshot path stays intact.
assert 'home-hero-hq-screenshots' in wf and 'test326HomeHeroHQScreenshots' in wf
assert 'AVDB-340-home-screenshots' in wf

doc = (r/'Build327-DetailAuth.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '327' in doc and 'jointly' in doc.lower()

sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
detail = sdk.split('public func movieDetail(_ id: String')[1].split('public func movieDetailFull')[0]
full = sdk.split('public func movieDetailFull(_ id: String')[1].split('public func movieMagnets')[0]
assert 'useToken: true' in detail and 'useToken: true' in full
assert 'cachePolicy: movieDetailCachePolicy()' in detail and 'cachePolicy: movieDetailCachePolicy()' in full
assert 'reloadIgnoringLocalCacheData' in sdk
assert 'useProtocolCachePolicy' in sdk
assert 'if let token = client.token, !token.isEmpty' in sdk
# Do not invent tokens; Authorization is attached only when a token exists.
client = (r/'AVDB/Networking/APIClient.swift').read_text()
assert 'if useToken' in client and 'Bearer \\(t)' in client
assert 'URLCache.shared.removeAllCachedResponses()' in client
set_token = client.split('public func setToken(_ token: String?)')[1].split('public var hasToken')[0]
assert 'removeAllCachedResponses()' in set_token
# needsReauth is not an identity change and must not clear the cache.
app = (r/'AVDB/AVDBApp.swift').read_text()
mark = app.split('func markNeedsReauth()')[1].split('func restoreLogin()')[0]
assert 'sessionStatus = .needsReauth' in mark
assert 'isLoggedIn = false' in mark
assert 'logout()' not in mark and 'setToken(nil)' not in mark
assert 'removeAllCachedResponses' not in mark

assert 'func isAuthenticationFailure' in client
assert 'JWTVerificationError' in client
assert '请登录' in client

fixture = json.loads((r/'scripts/fixtures/detail-auth-jwt-error.json').read_text())
assert fixture == {'success': 0, 'action': 'JWTVerificationError', 'message': '請登錄帳號'}

view = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
# White-on-white bug is gone: failure text is not hardcoded white on systemBackground.
fail = view.split('else if let err = vm.errorMessage')[1].split('scrollIndicators')[0]
assert 'foregroundStyle(.white)' not in fail
assert 'Color(.systemBackground)' not in view.split('.background {')[1].split('.safeAreaInset(edge: .top')[0]
assert 'detailPageBackground' in view
assert 'foregroundStyle(.primary)' in fail and 'colorScheme(.dark)' in fail
assert 'exclamationmark.triangle' in fail and 'foregroundColor(.orange)' in fail
assert '去登录' in fail and 'accessibilityIdentifier("detail-error-login")' in fail
assert 'accessibilityIdentifier("detail-error-message")' in fail
assert 'LoginView()' in view
assert 'await reloadDetail()' in view
assert '.avdbCatalogAccountChanged' in view
# Account-change handler reloads the current movie.
handler = view.split('.onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged))')[1].split('.sheet(isPresented: $showLogin)')[0]
assert 'await reloadDetail()' in handler
# Build 340: the view no longer marks the session rejected itself; it asks
# AppState to revalidate the credential against the profile endpoint, the
# single arbiter — one business endpoint's auth error proves nothing.
assert 'revalidateCredential()' in view
assert 'markNeedsReauth()' not in view

vm = view.split('final class MovieDetailViewModel')[1].split('func loadMagnets()')[0]
assert 'isAuthError' in vm
assert 'JavDBError.isAuthenticationFailure(error)' in vm
assert 'sdk: JavDBSDK = .shared' in view

content = (r/'AVDB/Views/ContentView.swift').read_text()
assert '--detail-auth-fixture' in content and '--detail-auth-network' in content
assert 'authErrorFixture' in content

unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class DetailAuth327Tests' in unit
assert 'test327MovieDetailAuthorizationAndCachePolicy' in unit
assert 'test327ProductionJWTPayloadIsAuthAndNotSuccess' in unit
assert 'test327MovieDetailHTTP200JWTIsAuthError' in unit
assert 'test327ViewModelLoadsMovieWhenTokenPresent' in unit
assert '請登錄帳號' in unit and 'JWTVerificationError' in unit
assert 'Authorization' in unit and 'reloadIgnoringLocalCacheData' in unit
assert 'useProtocolCachePolicy' in unit
assert 'MovieDetailViewModel(movieID: "m327", sdk: sdk)' in unit

ui = (r/'UITests/PosterNavigationTests.swift').read_text()
assert 'func test327DetailAuthErrorMessageVisible()' in ui
assert 'func test327DetailAuthLoginButtonPresence()' in ui
assert 'detail-error-message' in ui and 'detail-error-login' in ui
# Do not assert color contrast in UI tests.
auth_ui = ui.split('func test327DetailAuthErrorMessageVisible()')[1]
assert 'contrast' not in auth_ui.lower() and 'foregroundColor' not in auth_ui and 'foregroundStyle' not in auth_ui

# Out of scope: do not touch the 326 hero pipeline in this change set.
# (Hero files may exist; this test only checks 327 contracts.)

print('PASS detail-auth327 source contracts: token on detail fetch, cache policy, '
      'setToken cache clear, needsReauth retains token, visible paired error styling, '
      'login entry, account-change reload, tests wired, release 340')
