from pathlib import Path
import subprocess, tempfile, json, sys
root=Path(__file__).resolve().parents[1]
original=(root/'THIRD_PARTY/lut-v6.7.8.txt').read_text()
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
 // mode1 forces extreme flag into predictParams; classifiers may still disagree on isExtremeDark(info)
 const p=ref.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 const q=port.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 assert.deepStrictEqual(JSON.parse(JSON.stringify(q)),JSON.parse(JSON.stringify(p)), name+' mode '+mode);
 const rgb=Array.from(ref.generateLutData(33,p)); const rgba=port.cubeRGBA(['temp','tint','sat','bright','contrast','highlight','shadow'].map(k=>p[k]));
 for(let i=0;i<rgb.length;i++) assert.strictEqual(rgb[i],rgba[Math.floor(i/3)*4+i%3]);
 cases.push({name:name+mode,pixels,info,extreme:mode===1,high:mode===2,params:p,rgb:rgb.slice(0,120)});
 }
}
assert.strictEqual(port.sampleSkinStats([]),null);
// Cold-scene high-match protection (v6.7.8): low R/B+R/G+sat with moderate luma → high-match
const cold={skin_rb:1.1,skin_rg:1.1,skin_sat:0.2,skin_lum:0.4,full_hl_ratio:0.05,full_sh_ratio:0.1,no_skin_data:false,high_pixels:0};
assert.strictEqual(ref.isHighMatch(cold), true);
assert.strictEqual(port.isHighMatch(cold), true);
// Extreme-dark threshold change (v6.7.8): luma<0.28, hl<0.01, sh>0.24 (no R/B gate)
const dark={skin_rb:1.8,skin_lum:0.25,full_hl_ratio:0.005,full_sh_ratio:0.30,no_skin_data:false};
assert.strictEqual(ref.isExtremeDark(dark), true);
assert.strictEqual(port.isExtremeDark(dark), true);
assert.strictEqual(typeof port.analyzeMultiFrame, 'function');
assert.strictEqual(typeof port.median, 'function');
assert.strictEqual(port.median([1,3,2]), 2);
assert.strictEqual(port.median([1,2,3,4]), 2.5);
// Synthetic RGBA rasters with enough center skin for sampleFrame (≥150).
function makeSkinRGBA(w,h,rgb,jitter){
 const bytes=new Uint8ClampedArray(w*h*4);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const i=(y*w+x)*4;
  const j=(rnd()-0.5)*jitter;
  bytes[i]=Math.max(0,Math.min(255,Math.round((rgb[0]+j)*255)));
  bytes[i+1]=Math.max(0,Math.min(255,Math.round((rgb[1]+j)*255)));
  bytes[i+2]=Math.max(0,Math.min(255,Math.round((rgb[2]+j)*255)));
  bytes[i+3]=255;
 }
 return bytes;
}
const W=64,H=64;
const skinA=makeSkinRGBA(W,H,[0.62,0.45,0.38],0.04);
const skinB=makeSkinRGBA(W,H,[0.58,0.42,0.36],0.04);
const skinC=makeSkinRGBA(W,H,[0.66,0.48,0.40],0.04);
const single=port.analyzeFrame(Array.from(skinA),W,H,null);
assert.ok(single && single.params);
const multiOne=port.analyzeMultiFrame([{bytes:Array.from(skinA),width:W,height:H,box:null}]);
assert.ok(multiOne && multiOne.params);
assert.deepStrictEqual(JSON.parse(JSON.stringify(multiOne.params)), JSON.parse(JSON.stringify(single.params)));
assert.strictEqual(multiOne.frameCount,1);
// Manual median composition must match analyzeMultiFrame for three center frames.
const framesRaw=[skinA,skinB,skinC].map(b=>port.sampleFrame(b,W,H,null)).filter(f=>f && f.pixels);
assert.ok(framesRaw.length>=2, 'expected multiple sampled frames');
const stats=framesRaw.map(f=>port.sampleSkinStats(f.pixels)).filter(Boolean);
const med={
 skin_rb:port.median(stats.map(s=>s.skin_rb)),
 skin_rg:port.median(stats.map(s=>s.skin_rg)),
 skin_lum:port.median(stats.map(s=>s.skin_lum)),
 skin_sat:port.median(stats.map(s=>s.skin_sat)),
 full_contrast:port.median(stats.map(s=>s.full_contrast)),
 full_hl_ratio:framesRaw[0].full_hl_ratio_global,
 full_sh_ratio:port.median(stats.map(s=>s.full_sh_ratio)),
 high_rb:framesRaw[0].high_rb,
 high_pixels:framesRaw[0].high_pixels,
 regionName:framesRaw[0].regionName
};
let total=0; for(const f of framesRaw) total+=f.pixels.length;
const merged=new Float32Array(total); let off=0;
for(const f of framesRaw){ merged.set(f.pixels,off); off+=f.pixels.length; }
const useExtreme=port.isExtremeDark(med);
const useHigh=useExtreme?false:port.isHighMatch(med);
// Re-subsample via analyzeMultiFrame path
const multi=port.analyzeMultiFrame([skinA,skinB,skinC].map(b=>({bytes:Array.from(b),width:W,height:H,box:null})));
assert.ok(multi && multi.params);
assert.ok(multi.frameCount>=2);
assert.strictEqual(multi.usedFace,false);
assert.strictEqual(Math.abs(multi.info.skin_rb-med.skin_rb)<1e-12, true);
assert.strictEqual(Math.abs(multi.info.skin_lum-med.skin_lum)<1e-12, true);
// Face-box preference: mix a face-framed sample with center frames → only face contributes.
const faceBox={x1:8,y1:8,x2:56,y2:56};
const faceMulti=port.analyzeMultiFrame([
 {bytes:Array.from(skinA),width:W,height:H,box:null},
 {bytes:Array.from(skinB),width:W,height:H,box:faceBox},
 {bytes:Array.from(skinC),width:W,height:H,box:null}
]);
assert.ok(faceMulti && faceMulti.usedFace===true);
assert.strictEqual(faceMulti.info.regionName,'人脸框');
assert.strictEqual(faceMulti.frameCount,1);
assert.strictEqual(multi.sceneGuard, false);
// Scene-change guard: divergent skin_lum/rb must NOT median mixed scenes.
const skinDark=makeSkinRGBA(W,H,[0.28,0.20,0.18],0.02);
const skinBright=makeSkinRGBA(W,H,[0.78,0.62,0.55],0.02);
const mixed=port.analyzeMultiFrame([
 {bytes:Array.from(skinA),width:W,height:H,box:null},
 {bytes:Array.from(skinDark),width:W,height:H,box:null},
 {bytes:Array.from(skinBright),width:W,height:H,box:null}
]);
assert.ok(mixed && mixed.params);
assert.strictEqual(mixed.sceneGuard, true);
assert.ok(mixed.frameCount >= 1 && mixed.frameCount < 3, 'scene guard should drop mixed frames, got '+mixed.frameCount);
// Coherent pair + one outlier → keep the coherent cluster (size 2).
const skinA2=makeSkinRGBA(W,H,[0.61,0.44,0.37],0.03);
const outlier=makeSkinRGBA(W,H,[0.22,0.16,0.14],0.02);
const cluster=port.analyzeMultiFrame([
 {bytes:Array.from(skinA),width:W,height:H,box:null},
 {bytes:Array.from(skinA2),width:W,height:H,box:null},
 {bytes:Array.from(outlier),width:W,height:H,box:null}
]);
assert.ok(cluster && cluster.sceneGuard===true);
assert.strictEqual(cluster.frameCount, 2);
// Face-preferred + scene guard: divergent face frames → best coherent face cluster / single.
const faceDarkBox={x1:8,y1:8,x2:56,y2:56};
const faceMix=port.analyzeMultiFrame([
 {bytes:Array.from(skinA),width:W,height:H,box:faceBox},
 {bytes:Array.from(skinDark),width:W,height:H,box:faceDarkBox},
 {bytes:Array.from(skinC),width:W,height:H,box:null}
]);
assert.ok(faceMix && faceMix.usedFace===true);
assert.ok(faceMix.frameCount<=2);
assert.strictEqual(typeof port.selectCoherentPairs, 'function');
assert.strictEqual(port.SCENE_GUARD_LUM_SPAN, 0.08);
assert.strictEqual(port.SCENE_GUARD_RB_SPAN, 0.18);
fs.writeFileSync(process.argv[5],JSON.stringify(cases)); console.log('PASS: 21 staged searches, stats, 21 complete 33³ RGB cubes + v6.7.8 classifiers + multi-frame median + scene-guard: exact Node equality');
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
