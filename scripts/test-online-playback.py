from pathlib import Path
import platform,subprocess,tempfile,plistlib
R=Path(__file__).resolve().parents[1]
core=(R/'AVDB/Services/OnlinePlaybackCore.swift').read_text();panel=(R/'AVDB/Views/Player/OnlinePlaybackPanel.swift').read_text();extra=(R/'AVDB/Services/OnlineAdditionalProviders.swift').read_text()
assert 'OnlinePlaybackPanel(number: movie.displayNumber)' in (R/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'KSChromePlayer(' in panel and 'headers: plan.headers' in panel and '.id(plan.id)' in panel
assert 'publicSubtitleQuery: plan.number' in panel and 'supportsFramePreview: false' in panel
assert 'case thirdPartyAVDB, javmenu, av01, memojav, missav, jable' in core
assert 'URLSessionConfiguration.ephemeral' in core and 'c.httpShouldSetCookies = false' in core and 'c.urlCredentialStorage = nil' in core
assert 'completionHandler(nil)' in core and 'serverTrust' not in core
assert 'session.bytes(for: request)' in core and 'data.count < cap' in core
assert '< 120' in panel and 'selectionEpoch == epoch' in panel and 'epochs[source] == epoch' in panel
assert 'Task.sleep(nanoseconds: 25_000_000_000)' in panel and 'count >= 2' in panel
assert 'query.queryItems' in extra and 'memoProof' in extra and 'issued["comp"] as? Bool == true' in extra
assert 'JavDBSDK' not in core+extra+panel and 'APIClient.shared.token' not in core+extra+panel
assert 'evaluateJavaScript' not in core+extra+panel
assert plistlib.loads((R/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion']=='228'
print('PASS six-source production UI wiring/static privacy/size/timeout/cache/cancellation policies (not runtime claim)')
if platform.system()=='Darwin':
 with tempfile.TemporaryDirectory() as d:
  identity=Path(d)/'CatalogueIdentity.swift';s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text();identity.write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
  binary=str(Path(d)/'online-playback-tests')
  sources=[identity,R/'AVDB/Services/JavRankingCore.swift',R/'AVDB/Services/OnlinePlaybackCore.swift',R/'AVDB/Services/OnlineAdditionalProviders.swift',R/'AVDB/Views/Player/OnlinePlaybackPanel.swift',R/'scripts/OnlinePlaybackRegression.swift']
  subprocess.run(['swiftc','-target',platform.machine()+'-apple-macosx14.0','-swift-version','5','-D','DEBUG','-D','ONLINE_CORE_TEST',*map(str,sources),'-o',binary],check=True)
  subprocess.run([binary],check=True,timeout=90)
else:print('SKIP native Swift on Linux; mandatory macOS CI compiles and runs exact production sources')
