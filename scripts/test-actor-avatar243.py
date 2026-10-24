"""Execute avatar selection with a neutral fixture. No live person photos."""
import json, shutil, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
if not shutil.which("swiftc"):
    print("Avatar Swift execution requires macOS CI")
    raise SystemExit(0)
fixture = r'''
import Foundation
let names = ["中性演员甲", "Neutral Actor A"]
let unique = [TMDBPerson(id: 7, name: "Neutral Actor A", alsoKnownAs: ["中性演员甲"], gender: 1, profilePath: "/neutral.png")]
let selected = TMDBPersonSelector.select(unique, names: names)
precondition(selected.status == .matched && selected.personID == 7)
precondition(selected.url == "https://image.tmdb.org/t/p/w185/neutral.png")
let many = unique + [TMDBPerson(id: 8, name: "中性演员甲", alsoKnownAs: [], gender: nil, profilePath: "/other.png")]
precondition(TMDBPersonSelector.select(many, names: names).status == .ambiguous)
let noPath = [TMDBPerson(id: 9, name: "中性演员甲", alsoKnownAs: [], gender: 0, profilePath: nil)]
precondition(TMDBPersonSelector.select(noPath, names: names).status == .notFound)
precondition(TMDBPersonSelector.select([], names: names).status == .notFound)
precondition(ActorAvatarFallback.officialURL(profilePath: "../secret.png") == nil)
struct NeutralActor: Decodable { let avatarURL: String?; let coverURL: String? }
let owned = try JSONDecoder().decode(Actor.self, from: JSONSerialization.data(withJSONObject: ["id":"owned","name":"中性演员甲","avatar_url":"https://example.invalid/owned.png"]))
let ownedLookup = await ActorAvatarFallback.resolve(actor: owned, names: names) { _ in
    preconditionFailure("existing avatar must not search")
}
precondition(ownedLookup.status == .existing)
ActorAvatarFallback.resetCache()
let missing = try JSONDecoder().decode(Actor.self, from: JSONSerialization.data(withJSONObject: ["id":"missing","name":"中性演员甲"]))
var calls = 0
let first = await ActorAvatarFallback.resolve(actor: missing, names: names) { _ in
    calls += 1
    return ActorAvatarLookup(status: .notFound, url: nil, personID: nil)
}
let second = await ActorAvatarFallback.resolve(actor: missing, names: names) { _ in
    calls += 1
    return ActorAvatarLookup(status: .matched, url: "https://example.invalid/should-not-repeat", personID: 1)
}
precondition(first.status == .notFound && second.status == .notFound && calls == 1, "not-found cached")
ActorAvatarFallback.resetCache()
let cancelled = await ActorAvatarFallback.resolve(actor: missing, names: names) { _ in throw CancellationError() }
let afterCancel = await ActorAvatarFallback.resolve(actor: missing, names: names) { _ in
    ActorAvatarLookup(status: .matched, url: "https://image.tmdb.org/t/p/w185/neutral.png", personID: 7)
}
precondition(cancelled.status == .cancelled && afterCancel.status == .matched, "cancellation is not cached")
let missingKey = try await TMDBPersonClient.search(names: names, apiKey: nil)
precondition(missingKey.status == .missingKey)
print("PASS actor avatar boundaries")
'''
source = (root / "AVDB/Services/ExternalActorResolver.swift").read_text()
marker = "struct TMDBAvatarTokenStore"
main = "import SwiftUI\n" + source.replace(marker, "import SwiftUI\n" + marker, 1) + "\n@main struct Runner {\n static func main() async {\n" + fixture + "\n }\n}\n"
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / "main.swift").write_text(main)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(path / "main.swift"), "-o", str(path / "avatar")], check=True)
    subprocess.run([str(path / "avatar")], check=True, timeout=20)
