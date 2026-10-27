"""Static guards for JavDay online adapter + MissAV 403 mitigations (no live adult media)."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
core = (R / 'AVDB/Services/OnlinePlaybackCore.swift').read_text()
extra = (R / 'AVDB/Services/OnlineAdditionalProviders.swift').read_text()
adapters = (R / 'AVDB/Services/DetailOnlineAdapters.swift').read_text()
missav_core = (R / 'AVDB/Services/MissAVCore.swift').read_text()
missav_src = (R / 'AVDB/Services/MissAVSource.swift').read_text()
assert 'case jable, missav, av123, memojav, javday' in core
assert 'case .javday: return "JavDay"' in core
assert 'javday.app' in core and 'javday.homes' in core
assert 'func javdayMedia' in extra and 'JavDayAdapter' in adapters
assert 'search/wd/' in adapters
assert 'for attempt in 0...2' in missav_src
assert 'hasCards' in missav_core and 'please wait' in missav_core
assert 'evaluateJavaScript' not in core + extra + adapters
assert 'Widget.' not in core + extra + adapters + missav_src
print('PASS javday267 static source/policy/missav-retry guards')
