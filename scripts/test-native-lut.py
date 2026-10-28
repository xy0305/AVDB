from pathlib import Path
import subprocess, tempfile, json, sys
root=Path(__file__).resolve().parents[1]
original=(root/'THIRD_PARTY/lut-v6.7.5.txt').read_text()
# Independent oracle: evaluate original lexical numeric section, not shipped extraction.
a=original.index('    const CONFIG = {'); b=original.index('    function getOrCreateOverlayRoot')
c=original.index('    const KR ='); d=original.index('    // ============================================================\n    // 四、MediaPipe 加载')
oracle='var console={log(){}};'+original[a:b]+original[c:d]
exports='({sampleSkinStats,predictParams,generateLutData,applyParamsToSkinArray,isExtremeDark,isHighMatch})'
js=r'''
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const engine=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),engine);
const original=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[3],'utf8'),original);
const ref=vm.runInContext(process.argv[4],original),port=engine.OriginalLUT;
let seed=154;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;}
const cases=[];
for(const [name,base] of [['dark',[.16,.13,.12]],['bright',[.85,.76,.64]],['highmatch',[.58,.45,.40]],['yellow',[.7,.43,.24]],['black',[0,0,0]],['white',[1,1,1]],['red',[1,0,0]]]){
 let pixels=[];for(let i=0;i<60;i++)for(const c of base)pixels.push(Math.min(1,Math.max(0,c+(rnd()-.5)*.12)));
 const stats=ref.sampleSkinStats(new Float32Array(pixels));
 assert.deepStrictEqual(JSON.parse(JSON.stringify(port.sampleSkinStats(new Float32Array(pixels)))),JSON.parse(JSON.stringify(stats)));
 for(const mode of [0,1,2]){
 const info={...stats,high_rb:mode===2?1.4:1,high_pixels:mode===2?6000:0,regionName:mode===2?'中央50%':'人脸框'};
 if(name==='bright')info.full_hl_ratio=.7;
 const p=ref.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 const q=port.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 assert.deepStrictEqual(JSON.parse(JSON.stringify(q)),JSON.parse(JSON.stringify(p)));
 const rgb=Array.from(ref.generateLutData(33,p)); const rgba=port.cubeRGBA(['temp','tint','sat','bright','contrast','highlight','shadow'].map(k=>p[k]));
 for(let i=0;i<rgb.length;i++) assert.strictEqual(rgb[i],rgba[Math.floor(i/3)*4+i%3]);
 cases.push({name:name+mode,pixels,info,extreme:mode===1,high:mode===2,params:p,rgb:rgb.slice(0,120)});
 }
}
assert.strictEqual(port.sampleSkinStats([]),null);
fs.writeFileSync(process.argv[5],JSON.stringify(cases)); console.log('PASS: 21 staged searches, stats, 21 complete 33³ RGB cubes: exact Node equality');
'''
with tempfile.TemporaryDirectory() as tmp:
 t=Path(tmp);(t/'oracle.js').write_text(oracle);(t/'test.js').write_text(js)
 subprocess.run(['node',str(t/'test.js'),str(root/'AVDB/Resources/OriginalLUT.js'),str(t/'oracle.js'),exports,str(t/'cases.json')],check=True)
 if sys.platform!='darwin':
  print('JavaScriptCore differential requires macOS CI; NOT claimed locally.');sys.exit(0)
 swift=r'''
import Foundation
import JavaScriptCore
let context = JSContext()!
context.evaluateScript(try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let cases = try JSONSerialization.jsonObject(with: data) as! [[String:Any]]
let api = context.objectForKeyedSubscript("OriginalLUT")!
for c in cases {
 context.setObject(c["pixels"], forKeyedSubscript: "inputPixels" as NSString)
 let pixels = context.evaluateScript("new Float32Array(inputPixels)")!
 let p = api.objectForKeyedSubscript("predictParams")!.call(withArguments: [c["info"]!,pixels,c["extreme"]!,c["high"]!])!
 precondition(context.exception == nil, "JavaScriptCore exception")
 let expected = c["params"] as! [String:NSNumber]
 let actual = p.toDictionary() as! [String:NSNumber]
 precondition(expected == actual, "parameter parity mismatch")
 let rgb = api.objectForKeyedSubscript("generateLutData")!.call(withArguments:[33,p])!
 context.setObject(rgb, forKeyedSubscript:"testRGB" as NSString)
 let out = context.evaluateScript("Array.from(testRGB).slice(0,120)")!.toArray() as! [NSNumber]
 let want = c["rgb"] as! [NSNumber]
 for i in out.indices { precondition(abs(out[i].doubleValue-want[i].doubleValue) <= 1e-7) }
}
print("PASS: native JavaScriptCore vs independent original Node oracle: 21 searches and LUT scalar samples (1e-7)")
'''
 (t/'main.swift').write_text(swift)
 subprocess.run(['swift',str(t/'main.swift'),str(root/'AVDB/Resources/OriginalLUT.js'),str(t/'cases.json')],check=True)
