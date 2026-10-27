"""266: curated Gfriends HQ single-person portraits + large TMDB profile."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
service = (R / "AVDB/Services/JavBusActorAvatar.swift").read_text().split("// MARK: - Native shared presentation")[0]
resolver = (R / "AVDB/Services/ExternalActorResolver.swift").read_text()
ui = (R / "AVDB/Services/JavBusActorAvatar.swift").read_text().split("// MARK: - Native shared presentation")[1]

assert "enum GfriendsPortraits" in service
assert "Walk curated agencies in priority order" in service
for group in ["6-Tpowers", "1-FALENO", "0-Hand-Storage", "2-Juicy-Honey", "3-MUTEKI", "7-S1", "8-Ideapocket", "v-Prestige"]:
    assert f'"{group}"' in service, group
for banned in ["y-Minnano", "y-AVDC", "z-DMM", "9-Javrave", "8-Warashi", "z-Derekhsu"]:
    assert banned not in service, banned
assert "select(index:" in service
assert "GfriendsPortraits.lookup" in ui
assert "https://image.tmdb.org/t/p/h632" in resolver
assert "https://image.tmdb.org/t/p/w185" not in resolver
assert "Existing AVDB artwork always wins" in resolver or "existing AVDB artwork" in ui.lower() or "Valid originals win" in (R/"Build252-ActorPortraits.md").read_text()
note = (R / "Build266-ActorHQPortraits.md").read_text()
assert "1-FALENO" in note and "h632" in note
print("PASS actor HQ portraits 266 contract")
