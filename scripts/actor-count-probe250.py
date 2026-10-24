import os, pathlib, subprocess
R = pathlib.Path(__file__).resolve().parents[1]
def read(p): return (R / p).read_text()
def decl(s, mark):
    start = s.index(mark)
    a = s.index("{", start)
    depth = 1
    i = a + 1
    while depth:
        depth += (s[i] == "{") - (s[i] == "}")
        i += 1
    return s[start:i]
sdk = read("AVDB/Services/JavDBSDK.swift")
model = read("AVDB/Models/Movie.swift")
parts = ["import Foundation", read("AVDB/Models/JSONFlex.swift"), decl(read("AVDB/Models/User.swift"), "public struct User:"), read("AVDB/Networking/JavDBSignature.swift"), read("AVDB/Networking/APIClient.swift"), decl(model, "public struct Actor:"), decl(sdk, "public struct ActorListData:")]
header = sdk[sdk.index("@MainActor\npublic final class JavDBSDK"):sdk.index("    // Memory only")]
parts.append(header + decl(sdk, "    public func searchActors(") + "\n}")
resolver = read("AVDB/Services/ExternalActorResolver.swift").split("enum ActorAvatarLookupStatus:")[0].replace("import Security", "").replace("import SwiftUI", "")
parts.append(read("AVDB/Services/ActorAliasCatalog.swift"))
parts.append(resolver)
parts.append(read("scripts/ActorCountProbe250.swift"))
p = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "ActorCountProbe250.swift"
p.write_text("\n".join(parts))
binary = p.with_suffix("")
subprocess.run(["swiftc", "-parse-as-library", str(p), "-o", str(binary)], check=True)
subprocess.run([str(binary), str(R / "AVDB/Resources/JavVerseSnapshot.json"), str(R / "AVDB/Resources/ActorAliasIndex.json")], check=True)
