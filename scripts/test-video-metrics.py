from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
player = (root/'AVDB/Views/Player/PlayerView.swift').read_text()
pan = (root/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert 'av.player.currentItem?.presentationSize' in player
assert 'let size = engine.naturalSize' in player and 'evidence: .track' in player
assert 'onVideoMetrics: ((URL, PlaybackVideoMetrics?, Bool) -> Void)? = nil' in player
assert 'publishVideoMetrics(timedOut: Date().timeIntervalSince(start) > 30)' in player
assert 'value != lastVideoMetrics || settled != metricsSettled' in player
assert 'guard !Task.isCancelled else { return }' in player
assert '.id(metricsGeneration)' in pan and '.id(url)' in pan
assert 'generation: metricsGeneration)' in pan
assert '@Published private(set) var activeStream' in pan
assert '✓ 正在播放 · ' in pan and '.confirmationDialog("播放源"' in pan
assert 'Text(vm.resolutionDetail' in pan
failure = pan[pan.index('    func failed()'):pan.index('    func selectEpisode')]
assert 'streams = streams.filter { $0.isOriginal } + list' in failure and 'activate(first)' in failure
assert 'activate(fresh)' in failure
# Compile the actual source policy and shipping VM methods, not a duplicated policy.
def method(signature):
    start = pan.index(signature)
    brace = pan.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (pan[end] == '{') - (pan[end] == '}')
        end += 1
    return pan[start:end].replace('private func', 'func')
harness = '''import Foundation
enum Pan115Client {
 struct PlayStream { var name: String; var url: String; var isOriginal: Bool }
}
@MainActor final class ShippingHarness {
 var activeStream: Pan115Client.PlayStream?
 var videoMetrics = PlaybackMetricsState()
 var qualityLabel = ""
 var playURL: URL?
 var metricsGeneration: Int { videoMetrics.generation }
 var resolutionDetail: String { videoMetrics.detail }
'''
for signature in ['    func isCurrent(', '    func receiveMetrics(', '    private func clearMetrics(', '    private func activate(']:
    harness += method(signature) + '\n'
harness += '}\n'
print('PASS static metrics callback, UI, fallback and lifecycle contracts', flush=True)
if sys.platform == 'darwin':
    with tempfile.TemporaryDirectory() as temp:
        p = Path(temp)
        (p/'Harness.swift').write_text(harness)
        subprocess.run(['swiftc','-swift-version','5',str(root/'AVDB/Views/Player/PlaybackVideoMetrics.swift'),str(p/'Harness.swift'),str(root/'scripts/VideoMetricsRegression.swift'),'-o',str(p/'tests')], check=True)
        subprocess.run([str(p/'tests')],check=True,timeout=30)
else:
    print('SKIP Swift executable metrics tests locally: requires macOS CI')
