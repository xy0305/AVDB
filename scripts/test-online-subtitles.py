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
print('PASS subtitle static privacy/wiring and no-background presentation contracts (not native runtime claims)')
if platform.system()=='Darwin':
 with tempfile.TemporaryDirectory() as d:
  binary=str(Path(d)/'subtitle-tests')
  subprocess.run(['swiftc','-swift-version','5','-D','SUBTITLE_CORE_TEST',str(root/'AVDB/Views/Player/OnlineSubtitle.swift'),str(root/'scripts/OnlineSubtitleRegression.swift'),'-o',binary],check=True)
  subprocess.run([binary],check=True,timeout=45)
else: print('SKIP native Swift on Linux; macOS CI compiles production source')
