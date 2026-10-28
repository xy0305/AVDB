from pathlib import Path
import subprocess,tempfile,sys
r=Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
 print('NOT RUN: actual JavaScriptCore requires macOS');sys.exit(0)
s=r'''
import Foundation
import JavaScriptCore
let ctx=JSContext()!
ctx.evaluateScript(try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8))
let fixtures=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
for f in fixtures {
 let api=ctx.objectForKeyedSubscript("Desktop83")!
 let result=api.objectForKeyedSubscript("predict")!.call(withArguments:[f["a"]!,f["info"]!])!.toDictionary()!
 let a=result["values"] as! [Double],b=f["params"] as! [Double]
 precondition(a==b,"Python oracle parameter mismatch")
 let colors:[[Double]]=[[0,0,0],[1,1,1],[0.3,0.5,0.7],[0.8,0.9,0.7]]
 let expected=f["rgb"] as! [[Double]]
 for (i,rgb) in colors.enumerated() {
  let output=api.objectForKeyedSubscript("pixel")!.call(withArguments:[rgb,a,false])!.toArray() as! [Double]
  precondition(zip(output,expected[i]).allSatisfy{abs($0-$1)<1e-12})
 }
 precondition(ctx.exception==nil)
}
print("PASS actual macOS JavaScriptCore all three template predictions and pixel values vs isolated Python oracle: \(fixtures.count)")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text(s)
 subprocess.run(['swift',str(p),str(r/'AVDB/Resources/OriginalLUT.js'),str(r/'scripts/fixtures83-full.json')],check=True)
