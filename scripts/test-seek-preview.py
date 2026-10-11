#!/usr/bin/env python3
"""Static wiring contracts + executable production-policy/AVFoundation test on macOS."""
from pathlib import Path
import platform
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
player = (root/'AVDB/Views/Player/PlayerView.swift').read_text()
preview = (root/'AVDB/Views/Player/SeekPreview.swift').read_text()
pan = (root/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert 'seekPreview.configure(url: url, headers: headers' in player
assert 'supportsFramePreview: vm.supportsFramePreview' in pan
assert 'activeStream?.isOriginal == true' in pan
assert 'thumbnailImageAtCurrentTime' not in preview
assert 'AVURLAssetHTTPHeaderFieldsKey' in preview
assert 'appliesPreferredTrackTransform = true' in preview
assert '4_000_000_000' in preview and 'cancelAllCGImageGeneration' in preview
assert '24, byteLimit: 8 * 1024 * 1024' in preview
assert 'geo.safeAreaInsets' in player and 'geometry.size.width * fraction' in player
assert 'else if isSeeking && !horizontalDrag' in player
assert '原始画面 · 不含 LUT' in player
assert not any(x in preview for x in ['AVPlayer(', 'AVAudioSession', 'URLSession', 'write(to:'])
print('PASS: static preview wiring/security/lifecycle contracts (not runtime claims)')
if platform.system() == 'Darwin':
    with tempfile.TemporaryDirectory() as tmp:
        executable = str(Path(tmp)/'seek-preview-tests')
        subprocess.run(['swiftc', '-swift-version', '5', str(root/'AVDB/Views/Player/SeekPreview.swift'),
                        str(root/'scripts/SeekPreviewRegression.swift'), '-o', executable], check=True)
        subprocess.run([executable], check=True, timeout=45)
else:
    print('SKIP: AVFoundation/Swift executable tests require macOS; CI runs them')
