"""Static guards: Jable online apex is fs1.app; no silent jable.tv→fs1 rewrite of response hosts."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
adapters = (R / 'AVDB/Services/DetailOnlineAdapters.swift').read_text()
core = (R / 'AVDB/Services/OnlinePlaybackCore.swift').read_text()
extra = (R / 'AVDB/Services/OnlineAdditionalProviders.swift').read_text()
reg = (R / 'scripts/OnlineRegression254.swift').read_text()
assert 'https://fs1.app/search/' in adapters
assert 'jable.tv/search' not in adapters
assert 'url.host == "fs1.app"' in core
assert 'https://fs1.app' in core
# policy must not accept jable.tv as online metadata host
block = core.split('case .jable:')[1].split('case .missav:')[0]
assert 'jable.tv' not in block or 'Reject jable.tv' in block
assert 'url.host == "jable.tv"' not in block
assert 'https://fs1.app/' in extra
assert 'wrong mirror' in reg and 'h=="fs1.app"' in reg
assert 'evaluateJavaScript' not in adapters + core
assert 'HTTPCookieStorage.shared' not in adapters + core
print('PASS jable270 online fs1.app apex / no silent rewrite guards')
