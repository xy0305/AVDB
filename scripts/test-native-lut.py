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
// Build 278 dark-fabric / shadow-detail contract on the shipped cube (black point, no crush, source hue).
function cubeAt(rgb,ri,gi,bi){const e=(bi*1089+gi*33+ri)*3;return [rgb[e],rgb[e+1],rgb[e+2]];}
const Yl=c=>.2126*c[0]+.7152*c[1]+.0722*c[2];
function toeContract(q,rgb,label){
 const T=port.CONFIG.shadowToe, slope=port.shadowToeSlope(q);
 assert.ok(slope>=T.slopeMin-1e-12 && slope<=T.slopeMax+1e-12, label+' toe slope '+slope);
 const k=cubeAt(rgb,0,0,0); assert.ok(Math.max(...k)<=1e-9, label+' black lifted '+k);
 let prev=-1;
 for(let i=0;i<=16;i++){
  const v=i/32, out=Yl(cubeAt(rgb,i,i,i));
  assert.ok(out>=prev-1e-9, label+' neutral ramp non-monotonic at '+v);
  prev=out;
  if(i>0 && v<=T.toeFull) assert.ok(out/v>=T.slopeMin-1e-6 && out/v<=T.slopeMax+1e-6, label+' toe ratio '+(out/v)+' at '+v);
 }
 for(const [ri,gi,bi] of [[2,1,1],[1,1,2],[1,1,1],[2,2,1]]){
  const o=cubeAt(rgb,ri,gi,bi), src=[ri/32,gi/32,bi/32];
  if(Yl(src)>T.toeFull) continue;
  const s=o[1]/src[1];
  for(let c=0;c<3;c++) assert.ok(Math.abs(o[c]-src[c]*s)<1e-6, label+' dark fabric chroma shifted');
 }
 const d1=Yl(cubeAt(rgb,2,2,2))-Yl(cubeAt(rgb,1,1,1));
 assert.ok(d1>=T.slopeMin*(1/32)-1e-6, label+' shadow step crushed '+d1);
}
// Build 278 highlight shoulder: coloured ramp stays monotonic and below the ceiling (no plateau / no blow-out).
function shoulderContract(q,label){
 const SH=port.CONFIG.shoulder; let prev=-1;
 const px=[];for(let i=0;i<=40;i++){const v=0.5+i/80;px.push(v,v*.80,v*.66);}
 const o=port.renderArray(new Float32Array(px),q);
 for(let i=0;i<o.length;i+=3){const y=Yl([o[i],o[i+1],o[i+2]]);assert.ok(y>=prev-1e-6,label+' shoulder non-monotonic');assert.ok(y<=SH.ceil+1e-6,label+' above shoulder ceiling '+y);prev=y;}
}
// Build 278 skin: never rotated into magenta (mean skin hue below 0 deg = >360).
function skinNotMagenta(px,q,label){
 const a=port.meanHueSat(px), b=port.meanHueSat(port.renderArray(px,q)), SF=port.CONFIG.safety;
 if(!a || a.sat<SF.minSkinSat || a.sat>SF.maxSkinSat || a.lum<SF.minSkinLum || a.hue<SF.hueRange[0] || a.hue>SF.hueRange[1]) return;
 assert.ok(b.hue>=Math.min(0,a.hue-SF.magentaExtraRot)-0.5, label+' skin went magenta '+JSON.stringify([a,b,q]));
}
let same678=0,guarded=0;
for(const [name,base] of [['dark',[.16,.13,.12]],['bright',[.85,.76,.64]],['highmatch',[.58,.45,.40]],['yellow',[.7,.43,.24]],['black',[0,0,0]],['white',[1,1,1]],['red',[1,0,0]]]){
 let pixels=[];for(let i=0;i<60;i++)for(const c of base)pixels.push(Math.min(1,Math.max(0,c+(rnd()-.5)*.12)));
 const stats=ref.sampleSkinStats(new Float32Array(pixels));
 assert.deepStrictEqual(JSON.parse(JSON.stringify(port.sampleSkinStats(new Float32Array(pixels)))),JSON.parse(JSON.stringify(stats)));
 for(const mode of [0,1,2]){
 const info={...stats,high_rb:mode===2?1.4:1,high_pixels:mode===2?6000:0,regionName:mode===2?'中央50%':'人脸框'};
 if(name==='bright')info.full_hl_ratio=.7;
 const p=ref.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 const q=port.predictParams(info,new Float32Array(pixels),mode===1,mode===2);
 for(const k of ['temp','tint','sat','bright','contrast','highlight','shadow']){assert.strictEqual(typeof q[k],'number');assert.ok(isFinite(q[k]),name+' nonfinite '+k);}
 // Build 278: 6.7.8 params are the target; the safety gate may only move them when 6.7.8 itself fails.
 const ctx=port.safetyContext(null,new Float32Array(pixels));
 const f678=port.safetyFailure(ctx,Object.assign({},p));
 if(f678===null){ assert.deepStrictEqual(JSON.parse(JSON.stringify(q)),JSON.parse(JSON.stringify(p)), name+' mode '+mode+' must equal 6.7.8'); same678++; }
 else { guarded++; const r=port.safetyFailure(ctx,Object.assign({},q)); assert.ok(r===null || JSON.stringify(q)!==JSON.stringify(p), name+mode+' guard did not act on '+f678); }
 const rgbPort=Array.from(port.generateLutData(33,q));
 const rgba=port.cubeRGBA(['temp','tint','sat','bright','contrast','highlight','shadow'].map(k=>q[k]));
 for(let i=0;i<rgbPort.length;i++) assert.strictEqual(rgbPort[i],rgba[Math.floor(i/3)*4+i%3]);
 // Same params → identical to the 6.7.8 oracle cube outside the shadow toe and below the highlight shoulder knee.
 if(JSON.stringify(q)===JSON.stringify(p)){
  const rgb=Array.from(ref.generateLutData(33,p)), TOE=port.CONFIG.shadowToe, SH=port.CONFIG.shoulder;
  let checked=0;
  for(let e=0;e<rgb.length/3;e++){
   const r0=(e%33)/32,g0=(Math.floor(e/33)%33)/32,b0=Math.floor(e/1089)/32;
   if(.2126*r0+.7152*g0+.0722*b0 < TOE.toeEnd) continue;
   if(Yl([rgb[e*3],rgb[e*3+1],rgb[e*3+2]]) > SH.knee-1e-9 || Math.max(rgb[e*3],rgb[e*3+1],rgb[e*3+2]) >= 0.999) continue;
   for(let c=0;c<3;c++) assert.strictEqual(rgb[e*3+c],rgba[e*4+c]);
   checked++;
  }
  assert.ok(checked>5000,'oracle cube coverage '+checked);
 }
 toeContract(q,rgbPort,name+mode);
 shoulderContract(q,name+mode);
 if(mode!==1) skinNotMagenta(new Float32Array(pixels),q,name+mode);
 cases.push({name:name+mode,pixels,info,extreme:mode===1,high:mode===2,params:q,rgb:rgbPort.slice(0,120)});
 }
}
assert.ok(same678>=12, 'Build 278 must keep the 6.7.8 params on non-failing fixtures, got '+same678+' (guarded '+guarded+')');
// Build 278 regression: desktop-style params that crush the toe on 6.7.8 must keep near-black detail.
{
 const harsh={temp:-31,tint:5,sat:-1,bright:18,contrast:6,highlight:-7,shadow:2};
 const rgb=Array.from(port.generateLutData(33,harsh));
 toeContract(harsh,rgb,'harsh'); shoulderContract(harsh,'harsh');
 const oracleRgb=Array.from(ref.generateLutData(33,harsh));
 assert.ok(Yl(cubeAt(oracleRgb,1,1,1))<0.01, 'oracle toe expected crushed');
 assert.ok(Yl(cubeAt(rgb,1,1,1))>=0.029, 'mobile toe preserved');
}
// Build 278 per-frame safety on synthetic whole frames (skin centre + scene): magenta skin, blown highlights,
// dark sheer fabric. Each must pass the safety check after analyzeFrame, and stay 6.7.8 when 6.7.8 passes.
function makeScene(w,h,skin,scene,jit){
 const bytes=new Uint8ClampedArray(w*h*4);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const i=(y*w+x)*4, c=(x>w/4&&x<3*w/4&&y>h/4&&y<3*h/4)?skin:scene(x,y);
  const j=(rnd()-0.5)*jit;
  for(let k=0;k<3;k++) bytes[i+k]=Math.max(0,Math.min(255,Math.round((c[k]+j)*255)));
  bytes[i+3]=255;
 }
 return bytes;
}
seed=278;
const scenes=[
 ['pinkskin-wall',[.66,.50,.50],()=>[.45,.42,.40]],
 ['bright-window',[.78,.60,.50],(x,y)=>((x+y)%7<4?[.92,.90,.86]:[.80,.78,.74])],
 ['black-stocking',[.62,.45,.38],(x,y)=>(y>48?((x%3)?[.035,.03,.03]:[.09,.08,.08]):[.40,.36,.33])],
 ['yellow-room',[.70,.50,.34],()=>[.55,.48,.38]],
];
for(const [nm,skin,scene] of scenes){
 const W=96,H=64, bytes=makeScene(W,H,skin,scene,0.05);
 const res=port.analyzeFrame(Array.from(bytes),W,H,null); assert.ok(res&&res.params, nm+' no params');
 const fr=port.sampleFrame(new Uint8ClampedArray(bytes),W,H,null); fr.global_sample=port.globalSample(new Uint8ClampedArray(bytes),W,H);
 const coarseSkin=(()=>{const n=fr.pixels.length/3,m=Math.min(n,port.CONFIG.coarseSampleSize),o=new Float32Array(m*3),st=n/m;for(let i=0;i<m;i++){const s=Math.floor(i*st)*3;o[i*3]=fr.pixels[s];o[i*3+1]=fr.pixels[s+1];o[i*3+2]=fr.pixels[s+2];}return o;})();
 const ctx=port.safetyContext(fr.global_sample,coarseSkin);
 const f=port.safetyFailure(ctx,Object.assign({},res.params));
 assert.ok(f===null, nm+' still fails '+f+' '+JSON.stringify(res.params));
 const rgb=Array.from(port.generateLutData(33,res.params)); toeContract(res.params,rgb,nm); shoulderContract(res.params,nm);
 cases.push({name:'scene-'+nm,pixels:Array.from(fr.pixels.slice(0,3*400)),global:Array.from(fr.global_sample),info:res.info,extreme:res.stage==='极端暗部',high:res.stage==='高命中',params:null,rgb:null});
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
for(const c of cases){ if(c.params===null){ c.params=port.predictParams(c.info,new Float32Array(c.pixels),c.extreme,c.high,new Float32Array(c.global)); c.rgb=Array.from(port.generateLutData(33,c.params)).slice(0,120); } }
fs.writeFileSync(process.argv[5],JSON.stringify(cases)); console.log('PASS: Build278 6.7.8 params where safe ('+same678+' fixtures identical, '+guarded+' guarded) + toe/shoulder/magenta contracts + per-frame safety scenes + classifiers + multi-frame/scene-guard; cube self-consistency');
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
 var global: Any = NSNull()
 if let g = c["global"] { context.setObject(g, forKeyedSubscript: "inputGlobal" as NSString); global = context.evaluateScript("new Float32Array(inputGlobal)")! }
 let p = api.objectForKeyedSubscript("predictParams")!.call(withArguments: [c["info"]!,pixels,c["extreme"]!,c["high"]!,global])!
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
print("PASS: native JavaScriptCore vs Node: \(cases.count) searches (incl. Build 278 safety scenes) and LUT scalar samples (1e-7)")
'''
 (t/'main.swift').write_text(swift)
 subprocess.run(['swift',str(t/'main.swift'),str(root/'AVDB/Resources/OriginalLUT.js'),str(t/'cases.json')],check=True)
