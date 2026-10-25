from pathlib import Path
import platform,subprocess,tempfile,plistlib
R=Path(__file__).resolve().parents[1]
core=(R/'AVDB/Services/OnlinePlaybackCore.swift').read_text();panel=(R/'AVDB/Views/Player/OnlinePlaybackPanel.swift').read_text();adapters=(R/'AVDB/Services/DetailOnlineAdapters.swift').read_text()
assert 'case jable, missav, av123, memojav' in core
assert 'OnlinePlaybackSheet(number: movie.displayNumber, model: onlinePlaybackModel, versions: $onlineVersions)' in (R/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'headers: plan.headers' in panel and '.id(plan.id)' in panel and 'cancelSelection()' in panel
assert 'epochs[source] == epoch' in panel and 'selectionEpoch == epoch' in panel
assert 'c.httpShouldSetCookies = false' in core and 'completionHandler(nil)' in core
assert 'validateDNS(mode:' in core and 'data.count < cap' in core and 'session.bytes(for: request)' in core
assert 'evaluateJavaScript' not in core+adapters+panel
assert 'APIClient.shared.token' not in core+adapters+panel
assert plistlib.loads((R/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion']=='260'
print('PASS four-source detail/native-header/cancellation/privacy static guards')
if platform.system()!='Darwin':
 print('SKIP native Swift on Linux; mandatory macOS IPA CI executes actual production sources')
else:
 with tempfile.TemporaryDirectory() as d:
  identity=Path(d)/'CatalogueIdentity.swift';s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text();identity.write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
  files=['AVDB/Services/PlaybackDiagnostic.swift','AVDB/Services/JavRankingCore.swift','AVDB/Services/MissAVCore.swift','AVDB/Services/OnlinePlaybackCore.swift','AVDB/Services/OnlineAdditionalProviders.swift','AVDB/Services/DetailOnlineAdapters.swift','AVDB/Views/Player/OnlinePlaybackPanel.swift','scripts/OnlineSafetyRegression255.swift','scripts/OnlineRegression254.swift']
  binary=str(Path(d)/'online254')
  subprocess.run(['swiftc','-target',platform.machine()+'-apple-macosx14.0','-swift-version','5','-D','ONLINE_CORE_TEST',str(identity),*[str(R/f) for f in files],'-o',binary],check=True)
  subprocess.run([binary],check=True,timeout=240)
