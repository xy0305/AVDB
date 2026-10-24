"""Execute alias lookup with a neutral fixture. No live actor data."""
import shutil, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
if not shutil.which("swiftc"):
    print("Alias Swift execution requires macOS CI")
    raise SystemExit(0)
fixture = r'''
let index = ActorAliasIndex(schema: 1, actors: [
    .init(id: "map:0001", canonical: "中性演员甲", display: "中性演员甲", aliases: ["中性演员甲", "中性演員甲", "Neutral A"]),
    .init(id: "map:0002", canonical: "中性演员乙", display: "中性演员乙", aliases: ["中性演员乙"])
], conflicts: [.init(alias: "中性冲突", actors: ["中性演员甲", "中性演员乙"])])
let catalog = ActorAliasCatalog(index: index)
let traditional = catalog.lookup(["中性演員甲"])
let english = catalog.lookup(["neutral a"])
precondition(traditional?.id == "map:0001" && english?.id == traditional?.id, "many aliases one identity")
precondition(catalog.lookup(["中性冲突"]) == nil, "conflict rejected")
precondition(catalog.lookup(["中性冲突", "中性演员甲"])?.id == "map:0001", "nonconflict evidence remains")
precondition(catalog.lookup(["中性演员甲", "中性演员乙"]) == nil, "two identities rejected")
precondition(catalog.lookup(["未见过的同名"]) == nil, "unmapped same name not guessed")
let identity = ExternalActorIdentity.resolve(sourceName: "中性演員甲", aliases: ["Neutral A"], catalog: catalog)
precondition(identity.unified && identity.display == "中性演员甲" && identity.sourceName == "中性演員甲")
print("PASS actor alias lookup")
'''
main = (root / "AVDB/Services/ActorAliasCatalog.swift").read_text() + "\n@main struct Runner {\n static func main() {\n" + fixture + "\n }\n}\n"
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / "main.swift").write_text(main)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(path / "main.swift"), "-o", str(path / "alias")], check=True)
    subprocess.run([str(path / "alias")], check=True, timeout=20)
