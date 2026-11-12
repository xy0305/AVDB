#!/usr/bin/env python3
"""Build 338 logout access. Contracts: the manual 「退出登录」 button on the
「我的」 page is reachable in every state that holds a credential, not only
after the profile loads — the restoring state (正在恢复账户, isLoggedIn with
currentUser == nil) and the needsReauth state (327 policy: the credential
is retained on 401 while currentUser == nil) both carry the same
destructive button calling appState.logout(). The 327 automatic policy
itself is untouched: markNeedsReauth still retains the credential and
never calls logout()/setToken(nil); only the user can end the session.
Static source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '343' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 343;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 343' in wf and 'feat/logout-access-338' in wf
assert 'feat/recommender-throttle-337' in wf and 'feat/remove-javverse-336' in wf
assert wf.count('python3 scripts/test-logout-access338.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert 'scripts/package-lut343.py' in wf and 'AVDB-343-release' in wf and 'AVDB-337-release' not in wf
pkg = (r/'scripts/package-lut343.py').read_text()
assert "=='343'" in pkg and 'AVDB-unsigned-1.0.2-343-list-landscape-cover.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  logout-access-338:' in wf and '  recommender-throttle-337:' in wf

doc = (r/'Build338-LogoutAccess.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '338' in doc
assert 'unsigned' in doc.lower()

uv = (r/'AVDB/Views/User/UserView.swift').read_text()

# --- 1. Exactly three manual exits, all wired to the one AppState.logout() ---
assert uv.count('Button("退出登录", role: .destructive)') == 3
assert uv.count('appState.logout()') == 3

# --- 2. One in each state region of the account page ---
profile, rest = uv.split('} else if appState.isLoggedIn {', 1)
assert 'Button("退出登录", role: .destructive)' in profile  # loaded-profile state (pre-existing)
restoring, final_else = rest.split('} else {', 1)
assert 'Button("退出登录", role: .destructive)' in restoring  # 正在恢复账户 state (new in 338)
final_else = final_else.split('CoverTitleSettingsSection()', 1)[0]
assert '服务器已拒绝登录凭证，请重新登录' in final_else  # needsReauth footnote still shown
seg = final_else.split('if appState.sessionStatus == .needsReauth {')[-1]
assert 'Button("退出登录", role: .destructive)' in seg  # a needsReauth-conditional region carries the third button

# --- 3. The 327 automatic policy is untouched ---
app = (r/'AVDB/AVDBApp.swift').read_text()
assert 'Retain the credential' in app
block = app.split('func markNeedsReauth()', 1)[1].split('\n    }', 1)[0]
assert 'logout()' not in block and 'setToken' not in block  # rejection never clears the credential by itself
assert 'func logout()' in app and 'JavDBSDK.shared.logout()' in app  # the manual exit itself unchanged

print('PASS test-logout-access338: manual logout reachable in profile, restoring and '
      'needsReauth states (three identical buttons, one logout() path); the 327 '
      'retain-on-401 policy is untouched, release 343')
