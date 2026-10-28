"""Build 278 — avbase talent headshots + HQ cover preference contracts."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
meta = (R / "AVDB/Services/CatalogueMetadata.swift").read_text()
loader = (R / "AVDB/Services/ImageLoader.swift").read_text()
avatar = (R / "AVDB/Services/JavBusActorAvatar.swift").read_text()
note = (R / "Build278-AvbaseHQImages.md").read_text()

assert 'actor AvbasePortraitService' in meta
assert 'static func actorImage' in meta
assert 'static func parseTalent' in meta
assert 'www.avbase.net' in meta
assert '/mono/actjpgs/' in meta
assert 'HQ-first: large cover' in meta
assert 'coverRank' in meta
assert 'AvbasePortraitService.shared.lookup' in avatar
assert 'AvbaseMetadata.allowedDiscoveredImage(url)' in loader
assert 'talents/{name}' in note and 'pl.jpg' in note
assert 'Gfriends curated agency (HQ)' in note
print('PASS avbase portraits/covers 278 contract')
