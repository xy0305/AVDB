from pathlib import Path
import json, subprocess, tempfile
s = Path('AVDB/Services/Pan115Client.swift').read_text()
f = json.loads(Path('scripts/115-crypto-fixture.json').read_text())
crypto = s[s.index('private enum Pan115Crypto {'):].replace('private enum Pan115Crypto', 'enum Pan115Crypto')
arr = lambda x: '[' + ','.join(map(str,x)) + ']'
test = """
let key: [UInt8] = KEY
precondition(Pan115Crypto.derive(key, 4) == D4)
precondition(Pan115Crypto.derive(key, 12) == D12)
let raw: [UInt8] = INPUT
precondition(try Pan115Crypto.transform(raw) == OUTPUT)
for count in 0...250 {
    let bytes = (0..<count).map { UInt8($0 % 256) }
    precondition(Pan115Crypto.xor(Pan115Crypto.xor(bytes, key), key) == bytes)
}
let encoded = try Pan115Crypto.encode(Data(#"{"pickcode":"fixture"}"#.utf8), key: key)
precondition(Data(base64Encoded: encoded)!.count == 128)
for bad in ["", "!", Data([1,2,3]).base64EncodedString(), Data(repeating: 0, count:128).base64EncodedString()] {
    do { _ = try Pan115Crypto.decode(bad, key: key); fatalError("accepted malformed input") } catch {}
}
print("PASS: Security raw RSA vector, XOR derivation, randomized request, malformed response rejection")
"""
for name, field in [('KEY','key'),('D4','derived4'),('D12','derived12'),('INPUT','rawInput'),('OUTPUT','rawOutput')]: test = test.replace(name,arr(f[field]))
# Throwing calls cannot be inside precondition autoclosures.
test = test.replace('precondition(try Pan115Crypto.transform(raw) ==', 'let transformed = try Pan115Crypto.transform(raw)\nprecondition(transformed ==')
with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'main.swift'
    p.write_text('import Foundation\nimport Security\nenum Pan115Error: Error { case api(String) }\n'+crypto+test)
    subprocess.run(['swift',str(p)],check=True)
view=Path('AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert '!refreshUsed' in view and '!fallbackUsed' in view and 'guard !refreshing' in view
assert 'download_url' not in s[s.index('public func streamsForVideo'):s.index('public func originalStream')]
assert 'SecRandomCopyBytes' in s and 'Range"' not in s[s.index('public func originalStream'):s.index('/// 推送磁力并等到可播')]
print('PASS: bounded refresh/fallback and no metadata direct-link or static Range')
