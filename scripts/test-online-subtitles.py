from pathlib import Path
import platform,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'AVDB/Views/Player/OnlineSubtitle.swift').read_text()
player=(root/'AVDB/Views/Player/PlayerView.swift').read_text()
assert 'URLSessionConfiguration.ephemeral' in source
assert 'httpShouldSetCookies = false' in source
assert 'urlCredentialStorage = nil' in source
assert 'willPerformHTTPRedirection' in source
assert 'serverTrust' not in source and 'NSURLAuthenticationMethodServerTrust' not in source
assert 'appendHeader' not in source and 'Range' not in source
assert 'currentPlaybackTime' in player and 'OnlineSubtitleParser.display' in player
assert 'onlineSubtitles.clear()' in player
assert 'publicSubtitleQuery: movie.displayNumber' in (root/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert 'subtitle.search' in source and 'subtitle.disable' in source
caption = source.split('Text(renderedText)')[1].split('.scrollDisabled')[0]
assert '.foregroundStyle(.white)' in caption and '.shadow(color: .black' in caption
assert 'RoundedRectangle' not in caption and '.black.opacity(0.65)' not in caption
assert '@AppStorage("subtitle.fontPoints")' in source and '@AppStorage("subtitle.positionX")' in source
assert 'in: 14...36' in source and 'subtitle.appearance.reset' in source
assert '.allowsHitTesting(editing)' in source and '.highPriorityGesture(DragGesture' in source
assert 'safeArea.bottom + 12' in source and 'safeArea.bottom + 116' not in source
assert 'subtitle.nudge.left' in source and 'subtitle.nudge.down' in source
assert 'subtitle.selection.feedback' in source and 'subtitle.selection.box' in source
model=(root/'AVDB/Views/Player/OnlineSubtitleModel.swift').read_text()
provider=(root/'AVDB/Views/Player/SubtitleCatProvider.swift').read_text()
assert 'withTaskGroup' in provider and 'for await outcome in group' in provider
assert 'state.receive(outcome.source' in model and 'self.state.generation == epoch' in model
assert 'source.rawValue + ":" + q' in model and '< 120' in model
assert 'self.languages[row.id] = variants' in model
assert 'if row.ext == "html"' in model and 'fetch(row.url, .catDetail)' in model
assert 'model.cancelPending()' in source and '迅雷 + SubtitleCat + 海南鸡字幕池（同时搜索）' in source and 'subtitle.chickenRice.enabled' in source
assert '不会发送私人文件名' in source
assert 'JRHTML.tree(html)' in provider
assert 'boundDownloadURL == url' in source and 'redirects <= 5' in source
print('PASS dual-source parallel/manual-only/privacy/cache/epoch static wiring contracts')
print('PASS subtitle static privacy/wiring and no-background presentation contracts (not native runtime claims)')
if platform.system()=='Darwin':
 with tempfile.TemporaryDirectory() as d:
  binary=str(Path(d)/'subtitle-tests')
  identity=Path(d)/'CatalogueIdentity.swift'
  identity.write_text('import Foundation\n' + (root/'AVDB/Services/CatalogueMetadata.swift').read_text().split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0].join(['enum CatalogueIdentity {','']))
  subprocess.run(['swiftc','-swift-version','5','-D','SUBTITLE_CORE_TEST',str(identity),str(root/'scripts/ChickenRiceRegression.swift'),str(root/'AVDB/Services/JavRankingCore.swift'),str(root/'AVDB/Views/Player/SubtitleCatProvider.swift'),str(root/'AVDB/Views/Player/OnlineSubtitleModel.swift'),str(root/'AVDB/Views/Player/OnlineSubtitle.swift'),str(root/'scripts/DualSubtitleRegression.swift'),str(root/'scripts/DualSubtitleTransportRegression.swift'),str(root/'scripts/OnlineSubtitleRegression.swift'),'-o',binary],check=True)
  subprocess.run([binary],check=True,timeout=45)
else: print('SKIP native Swift on Linux; macOS CI compiles production source')
