"""Static guards: MissAV online apex is missav.fans; no silent ws→fans rewrite of response hosts."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
adapters = (R / 'AVDB/Services/DetailOnlineAdapters.swift').read_text()
core = (R / 'AVDB/Services/OnlinePlaybackCore.swift').read_text()
reg = (R / 'scripts/OnlineRegression254.swift').read_text()
assert 'https://missav.fans/en/search/' in adapters
assert 'missav.ws/en/search' not in adapters
assert 'url.host == "missav.fans"' in core
assert 'https://missav.fans' in core
# policy must not accept ws as online metadata host
block = core.split('case .missav:')[1].split('case .av123:')[0]
assert 'missav.ws' not in block
assert 'wrong mirror' in reg and "h==\"missav.fans\"" in reg
assert 'evaluateJavaScript' not in adapters + core
assert 'HTTPCookieStorage.shared' not in adapters + core
print('PASS missav269 online fans apex / no silent rewrite guards')
