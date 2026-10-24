"""243 offline contracts: alias index, cross-board wiring, avatar boundaries."""
import json, plistlib, unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
INDEX = json.loads((R / "AVDB/Resources/ActorAliasIndex.json").read_text())

def norm(value):
    return " ".join(value.casefold().split())

class Alias243(unittest.TestCase):
    def test_index_unique_and_conflicts_omitted(self):
        actors = INDEX["actors"]
        self.assertEqual(len(actors), 8115)
        self.assertEqual(len({a["id"] for a in actors}), 8115)
        self.assertEqual(len({norm(a["canonical"]) for a in actors}), 8115)
        owners = {}
        for actor in actors:
            for alias in actor["aliases"]:
                key = norm(alias)
                self.assertNotIn(key, owners)
                owners[key] = actor["id"]
        conflicts = {norm(item["alias"]) for item in INDEX["conflicts"]}
        self.assertGreaterEqual(len(conflicts), 173)
        self.assertTrue(conflicts.isdisjoint(owners))
        self.assertGreater(sum(len(a["aliases"]) for a in actors), 15000)

    def test_simplified_traditional_same_identity(self):
        by_alias = {norm(alias): actor for actor in INDEX["actors"] for alias in actor["aliases"]}
        simplified = by_alias[norm("爱花未满")]
        traditional = by_alias[norm("愛花未滿")]
        japanese = by_alias[norm("愛花あゆみ")]
        self.assertEqual(simplified["id"], traditional["id"])
        self.assertEqual(simplified["id"], japanese["id"])
        self.assertEqual(simplified["canonical"], "爱花未满")

    def test_same_name_without_mapping_is_not_guessed(self):
        policy = (R / "AVDB/Services/ActorAliasCatalog.swift").read_text()
        resolver = (R / "AVDB/Services/ExternalActorResolver.swift").read_text()
        self.assertIn("never guesses", policy)
        self.assertIn("conflicts[$0] == nil", policy)
        self.assertIn("ids.count == 1", policy)
        self.assertIn("AVDB IDs are never invented", resolver)
        self.assertIn("matches.count <= 1", resolver)

    def test_external_boards_call_shared_resolver(self):
        verse = (R / "AVDB/Services/JavVerseSource.swift").read_text()
        library = (R / "AVDB/Services/MissAVMetadata.swift").read_text()
        ranking = (R / "AVDB/Views/JavRankingView.swift").read_text()
        view = (R / "AVDB/Views/JavVerseView.swift").read_text()
        self.assertIn("JavVerseActorResolver.resolve(name: entry.label, aliases: entry.aliases", verse)
        self.assertIn("aliases: nameZh == nameJa ? [] : [nameZh]", verse)
        self.assertIn("ExternalActorIdentity.resolve", library)
        self.assertIn("ExternalActorResolver.match", library)
        self.assertIn("RankingActorMatchLink", ranking)
        self.assertIn("ExternalActorResolver.resolve", ranking)
        self.assertIn("entity.aliases ?? []", ranking)
        self.assertEqual(view.count("count: 3)"), 2)
        grok = view.split("private struct JavVerseGrokPage:", 1)[1]
        self.assertIn("List {", grok)
        self.assertNotIn("LazyVGrid", grok)
        self.assertIn("row.person.status", view)

    def test_existing_avatar_not_replaced_and_no_startup_batch(self):
        resolver = (R / "AVDB/Services/ExternalActorResolver.swift").read_text()
        verse = (R / "AVDB/Services/JavVerseSource.swift").read_text()
        self.assertIn("Existing AVDB artwork always wins", resolver)
        self.assertIn("actor.avatarURL ?? actor.coverURL ?? result.avatarURL", (R / "AVDB/Views/MissAVRankingView.swift").read_text())
        self.assertIn("if existing(actor) != nil", resolver)
        self.assertIn("First result is never chosen", resolver)
        self.assertIn("hits.count == 1", resolver)
        self.assertIn(".missingKey", resolver)
        self.assertIn("Cancellation is intentionally not cached", resolver)
        self.assertIn("https://image.tmdb.org/t/p/w185", resolver)
        self.assertNotIn("for actor in ActorAliasCatalog", verse)
        self.assertIn("prefix(20)", verse)

    def test_version_registration_and_preserved_releases(self):
        info = plistlib.loads((R / "AVDB/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "1.0.2")
        self.assertEqual(info["CFBundleVersion"], "243")
        project = (R / "AVDB.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count("CURRENT_PROJECT_VERSION = 243;"), 2)
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 17.0;", project)
        for name in ("ActorAliasCatalog.swift", "ExternalActorResolver.swift", "ActorAliasIndex.json"):
            self.assertIn(name, project)
        rankings = (R / "AVDB/Views/Rankings/RankingsView.swift").read_text()
        label = rankings.split("private var sourceMenuLabelContent: some View {", 1)[1].split("private func reload", 1)[0]
        self.assertIn('Text("来源")', label)
        self.assertNotIn("Image(", label)

if __name__ == "__main__":
    unittest.main()
