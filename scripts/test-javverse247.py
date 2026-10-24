"""Compile exact Foundation-only production prefix, not a handwritten schema.
No Combine/mapper stubs. Before source/data come from the immutable 246 commit.
"""
import hashlib, json, shutil, subprocess, tempfile, os, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
BASE = 'a6d4597b8819892917f75cc3555d3bc1afd75cfb'
SHA = 'ef24c1ad8b4fea0762f89e5fbf594bcaa32cc7cf331af21ba4ef9bb636e6184c'
assert shutil.which('swiftc'), 'Swift required: do not report skipped execution as pass'
def old(path):
    return subprocess.check_output(['git','show',BASE+':'+path], cwd=root)
def prefix(source):
    return source.split('@MainActor final class JavVerseMapper:',1)[0].replace('import Combine\n','')
runner = r'''
func errorInfo(_ error: Error) -> [String: String] {
    var keys: [CodingKey] = []; var kind = "other"; var missing = ""
    switch error {
    case DecodingError.keyNotFound(let k, let c): kind="keyNotFound"; keys=c.codingPath; missing=k.stringValue
    case DecodingError.typeMismatch(_, let c): kind="typeMismatch"; keys=c.codingPath
    case DecodingError.valueNotFound(_, let c): kind="valueNotFound"; keys=c.codingPath
    case DecodingError.dataCorrupted(let c): kind="dataCorrupted"; keys=c.codingPath
    default: break
    }
    var path = ""
    for k in keys { path += k.intValue.map { "[\($0)]" } ?? ((path.isEmpty ? "" : ".") + k.stringValue) }
    if !missing.isEmpty { path += "." + missing }
    return ["type":kind,"path":path,"missingKey":missing,"localizedDescription":error.localizedDescription]
}
@main struct Probe {
static func main() throws {
 let args = CommandLine.arguments
 let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
 let before = args[2] == "before"
 if before {
    do { _ = try JavVerseSnapshot.decode(data); fatalError("246 MUST fail") }
    catch { let info=errorInfo(error); precondition(info["type"] == "keyNotFound" && info["path"] == "boards[0].entries[0].aliases"); print(String(data:try JSONSerialization.data(withJSONObject:info,options:.sortedKeys),encoding:.utf8)!) }
    return
 }
 let s = try JavVerseSnapshot.decode(data)
 precondition(s.boards.count == 13 && s.grok?.people.count == 250)
 precondition(s.boards.flatMap(\.entries).allSatisfy { $0.aliases.isEmpty })
 let e = s.boards[0].entries[0]
 let memberwise = JavVerseEntry(rank:e.rank,kind:e.kind,label:e.label,sourceURL:e.sourceURL,code:e.code)
 precondition(memberwise.aliases.isEmpty)
 precondition(s.grok!.people[0].entry(rank:1).rank == 1)
 var root = try JSONSerialization.jsonObject(with:data) as! [String:Any]
 func mutated(_ key:String, _ value:Any?) throws -> Data {
   var obj=root; var boards=obj["boards"] as! [[String:Any]]; var entries=boards[0]["entries"] as! [[String:Any]]
   entries[0][key]=value; boards[0]["entries"]=entries; obj["boards"]=boards
   return try JSONSerialization.data(withJSONObject:obj)
 }
 for value:Any in [NSNull(), [String](), ["保持别名"]] {
    let v=try JavVerseSnapshot.decode(mutated("aliases",value))
    precondition(v.boards[0].entries[0].aliases == (value as? [String] ?? []))
 }
 for value:Any in ["wrong",42,[1]] {
    do { _ = try JavVerseSnapshot.decode(mutated("aliases",value)); fatalError("wrong type accepted") }
    catch { precondition(errorInfo(error)["type"] == "typeMismatch") }
 }
 for (key,value) in [("sourceURL","https://bad.invalid/"),("rank",999),("kind","unknown")] as [(String,Any)] {
    do { _ = try JavVerseSnapshot.decode(mutated(key,value)); fatalError("bad business value accepted") }
    catch { precondition(error is JavVerseFailure) }
 }
 #if FIXED
 do { _ = try JavVerseSnapshot.decode(mutated("rank",nil)); fatalError("missing rank accepted") }
 catch { precondition(JavVerseFailure.diagnostic(error).contains("[keyNotFound]：boards[0].entries[0].rank")) }
 do { _ = try JavVerseSnapshot.decode(mutated("aliases","SECRET_SENTINEL")); fatalError("bad aliases accepted") }
 catch {
   let text=JavVerseFailure.diagnostic(error)
   precondition(text.contains("[typeMismatch]：boards[0].entries[0].aliases") && !text.contains("SECRET_SENTINEL"))
 }
 do { _ = try JavVerseSnapshot.decode(Data("{broken".utf8)); fatalError("bad JSON accepted") }
 catch { precondition(JavVerseFailure.diagnostic(error).contains("[dataCorrupted]")) }
 precondition(JavVerseFailure.diagnostic(JavVerseFailure.missingResource).contains("[resourceMissing]"))
 precondition(JavVerseFailure.diagnostic(JavVerseFailure.unreadableResource).contains("[resourceRead]"))
 var bad=root; bad["preparedAt"]="2026-10-24T03:58:55"
 do { _ = try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject:bad)); fatalError("timezone-less accepted") }
 catch { precondition(JavVerseFailure.diagnostic(error).contains("[validation]")) }
 bad=root; var grok=bad["grok"] as! [String:Any]; var people=grok["people"] as! [[String:Any]]
 var scores=people[0]["scores"] as! [String:Int]; scores["total"]=10001
 people[0]["scores"]=scores; grok["people"]=people; bad["grok"]=grok
 do { _ = try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject:bad)); fatalError("bad score accepted") }
 catch { precondition(error is JavVerseFailure) }
 #endif
 // Other newly defaulted board fields are Optional: prove missing keys work.
 var bs=root["boards"] as! [[String:Any]]
 for i in bs.indices { for key in ["term","periodKey","periodEnd","selectionTitle"] { bs[i].removeValue(forKey:key) } }
 root["boards"]=bs
 _ = try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject:root))
 let result:[String:Any] = ["boards":s.boards.count,"entries":s.boards.reduce(0){$0+$1.entries.count},"grok":s.grok!.people.count,"aliases":"missing/null/array accepted, wrong type rejected","strictValidation":"source/rank/kind rejected","optionalBoardFields":"missing accepted"]
 print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
}
}
'''
with tempfile.TemporaryDirectory() as temp:
    p=Path(temp); data=old('AVDB/Resources/JavVerseSnapshot.json')
    assert hashlib.sha256(data).hexdigest()==SHA
    (p/'snapshot.json').write_bytes(data)
    results={'snapshot246SHA256':SHA,'exactProductionPrefix':True,'stubs':False}
    for mode,source in [('before',old('AVDB/Services/JavVerseSource.swift').decode()),('after',(root/'AVDB/Services/JavVerseSource.swift').read_text())]:
        (p/'main.swift').write_text(prefix(source)+runner)
        subprocess.run(['swiftc']+(['-D','FIXED'] if mode=='after' else [])+['-swift-version','5','-parse-as-library',str(p/'main.swift'),'-o',str(p/'probe')],check=True)
        out=subprocess.check_output([str(p/'probe'),str(p/'snapshot.json'),mode],text=True)
        print(mode,out.strip()); results[mode]=json.loads(out)
        if mode=='after':
            actual=Path(sys.argv[1]) if len(sys.argv)>1 else root/'AVDB/Resources/JavVerseSnapshot.json'
            assert actual.read_bytes()==data, 'Release bundle bytes changed from actual 246 snapshot'
            subprocess.run([str(p/'probe'),str(actual),'after'],check=True)
    dest=Path(os.environ.get('SCHEMA_REPORT','schema247.json'))
    dest.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
