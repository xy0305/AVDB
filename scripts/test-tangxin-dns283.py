#!/usr/bin/env python3
"""Build 283: proxy-aware DNS pre-flight (Loon/Surge/Clash fake-ip, NAT64) + search hides floating tab bar."""
import os, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
read = lambda p: (ROOT / p).read_text()
core, policy, diag, tangxin, view = (read('AVDB/Services/OnlinePlaybackCore.swift'), read('AVDB/Services/OnlineDNSPolicy.swift'),
    read('AVDB/Services/PlaybackDiagnostic.swift'), read('AVDB/Services/TangxinCore.swift'), read('AVDB/Views/TangxinView.swift'))
content, chrome, search = read('AVDB/Views/ContentView.swift'), read('AVDB/Views/TabBarChrome.swift'), read('AVDB/Views/Search/SearchView.swift')
pbx = read('AVDB.xcodeproj/project.pbxproj'); plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())

# DNS wiring: every OnlineTransport / OnlineMediaScope pre-flight goes through the proxy-aware policy
body = core[core.index('static func validateAddresses'):core.index('static func diagnostic(_ url: URL')]
assert 'OnlineDNSPolicy.evaluate(addresses' in body and 'OnlineDNSPolicy.tunnelProbe()' in body and 'OnlineDNSPolicy.summary' in body
assert 'if !publicAddress(address)' not in body, 'old all-public rule removed'
for host in ('"tangxinvlog.app"', '"t.5gcdn.xyz"', '"5gcdn.xyz"', '"javday.homes"', '"missav.fans"', '"fs1.app"', '"123av.com"', '"memojav.org"'):
    assert host in policy, host
assert 'CFNetworkCopySystemProxySettings' in policy and '__SCOPED__' in policy and 'getifaddrs' in policy, 'read-only proxy/VPN detection'
assert 'Loon/Surge/Clash' in diag and '(?: local=\\d+ tunnel=[01])?' in diag, 'user hint + summary format'
assert 'static func cdnHost' in tangxin and 'cdnHost(url.host)' in tangxin, 'Tangxin CDN apex for covers + HLS'
assert 'tangxin.image.failure' in view and 'catch { }' not in view[view.index('struct TangxinImage'):view.index('struct TangxinDetailView')], 'covers no longer fail silently'
# tab bar wiring
assert 'FloatingTabContainer(selection: $selectedTab)' in content and '.environment(\\.appTab, tab)' in content
assert 'AVDBNativeTabBar(selection: $selectedTab)' not in content, 'bar only via the container'
assert 'if !chrome.hidden(selected: selection)' in chrome and 'keyboardWillChangeFrameNotification' in chrome and 'keyboardWillHideNotification' in chrome
assert '.transition(.move(edge: .bottom)' in chrome and '.animation(.easeInOut' in chrome
assert '.modifier(HidesFloatingTabBar())' in search
for name in ('OnlineDNSPolicy.swift', 'TabBarChrome.swift'):
    assert pbx.count(f'/* {name} in Sources */') == 2 and pbx.count(f'path = {name};') == 1, name
assert int(plist['CFBundleVersion']) >= 283 and pbx.count(f"CURRENT_PROJECT_VERSION = {plist['CFBundleVersion']};") == 2

swiftc = shutil.which('swiftc')
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift (no swiftc)')
else:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        (td / 'stub.swift').write_text(re.search(r'enum OnlineDNSMode[^\n]*\n', core).group(0))
        (td / 'OnlineDNSPolicy.swift').write_text(policy)
        (td / 'main.swift').write_text(read('scripts/OnlineDNSRegression283.swift'))
        subprocess.run([swiftc, '-swift-version', '5', '-o', str(td / 't'), str(td / 'stub.swift'), str(td / 'OnlineDNSPolicy.swift'), str(td / 'main.swift')], check=True)
        r = subprocess.run([str(td / 't')], capture_output=True, text=True, timeout=60)
        print(r.stdout, end='')
        if r.returncode or 'PASS dns283' not in r.stdout: print(r.stderr); sys.exit('dns283 swift regression failed')
print('PASS test-tangxin-dns283 wiring: proxy-aware DNS in OnlineTransport/OnlineMediaScope (pages, covers, HLS), Tangxin CDN apex, visible cover failure, floating tab bar hidden for search/keyboard, pbxproj, version 283')
