"""Build 271: IPX-697 noMatch root-cause guards (Jable opaque slug + MissAV primary synthesis)."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
core = (R / 'AVDB/Services/OnlinePlaybackCore.swift').read_text()
adapters = (R / 'AVDB/Services/DetailOnlineAdapters.swift').read_text()
reg = (R / 'scripts/OnlineRegression254.swift').read_text()
note = (R / 'Build271-OnlineNoMatch-IPX697.md').read_text()

assert 'opaquePrimary' in core
assert 'ipx-697ntum' in note or 'opaque' in note.lower()
assert 'DEMO-123NTUM' in reg
assert 'demo-123ntum' in reg
assert 'demo-123-uncensored-leak' in reg
assert 'labelled only' in reg or 'uncensored-leak' in reg
assert 'synthesize the primary' in adapters or 'Synthesize' in adapters or 'synthesize' in adapters
assert 'https://missav.fans/en/' in adapters
assert 'allowVersions:true' in adapters  # evidence scan
assert 'memojav.org/video/IPX-697' in note and '404' in note
# No silent host rewrite
assert 'missav.ws/en/search' not in adapters
assert 'jable.tv/search' not in adapters
assert 'evaluateJavaScript' not in core + adapters
print('PASS online271 IPX-697 noMatch guards (opaque Jable + MissAV primary synthesis + MemoJav documented)')
