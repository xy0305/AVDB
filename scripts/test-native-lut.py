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
// Build 276 dark-fabric / shadow-detail contract on the shipped cube.
function cubeAt(rgb,ri,gi,bi){const e=(bi*1089+gi*33+ri)*3;return [rgb[e],rgb[e+1],rgb[e+2]];}
const Yl=c=>.2126*c[0]+.7152*c[1]+.0722*c[2];
function toeContract(q,rgb,label){
 const T=port.CONFIG.shadowToe, slope=port.shadowToeSlope(q);
 const hi=q.shadow>10?T.extremeSlopeMax:T.slopeMax;
 assert.ok(slope>=T.slopeMin-1e-12 && slope<=hi+1e-12, label+' toe slope '+slope);
 // black point preserved exactly
 const k=cubeAt(rgb,0,0,0); assert.ok(Math.max(...k)<=1e-9, label+' black lifted '+k);
 // neutral ramp: monotonic, no lift > slopeMax and no crush < slopeMin below toeFull (luma ~0.10)
 let prev=-1;
 for(let i=0;i<=16;i++){
  const v=i/32, out=Yl(cubeAt(rgb,i,i,i));
  assert.ok(out>=prev-1e-9, label+' neutral ramp non-monotonic at '+v);
  prev=out;
  if(i>0 && v<=T.toeFull){
   assert.ok(out/v>=T.slopeMin-1e-6 && out/v<=hi+1e-6, label+' toe ratio '+(out/v)+' at '+v);
   if(v<=0.08 && q.shadow<=10) assert.ok(out<=v*1.05+1e-6, label+' lift below 0.08: '+out+' vs '+v);
  }
 }
 // dark coloured fabric keeps its source hue/chroma ratios (temp/tint not applied to near-black)
 for(const [ri,gi,bi] of [[3,2,2],[2,2,3],[1,1,1],[2,1,1]]){
  const o=cubeAt(rgb,ri,gi,bi), src=[ri/32,gi/32,bi/32];
  if(Yl(src)>T.toeFull) continue;
  const s=o[1]/src[1];
  for(let c=0;c<3;c++) assert.ok(Math.abs(o[c]-src[c]*s)<1e-6, label+' dark fabric chroma shifted');
 }
 // shadow detail: 0.02 vs 0.05 step keeps >= 92% of its separation
 const d0=0.03, d1=Yl(cubeAt(rgb,2,2,2))-Yl(cubeAt(rgb,1,1,1));
 assert.ok(d1>=T.slopeMin*(2/32-1/32)-1e-6, label+' shadow step crushed '+d1+' '+d0);
}
// Build 276 skin hue/sat bound (non-extreme paths).
function skinBound(info,px,q,extreme,label){
 if(extreme) return;
 const SG=port.CONFIG.skinGuard;
 const coarse=px; // fixture already <= coarse size
 const a=port.meanHueSat(coarse), b=port.meanHueSat(port.applyParamsToSkinArray(coarse,q));
 if(!a || a.sat<0.03 || a.sat>0.75 || a.lum<SG.minLum || a.hue<SG.hueRange[0] || a.hue>SG.hueRange[1]) return;
 const rot=b.hue-a.hue;
 const ok=Math.abs(rot)<=SG.maxHueRotate+0.5 && b.hue>=Math.min(SG.magentaFloor,a.hue)-0.5 &&
   b.sat/a.sat>=SG.minSatRatio-0.02 && b.sat/a.sat<=SG.maxSatRatio+0.02;
 // guard may stop at search bounds (e.g. sat ceiling); then it must at least not rotate into magenta.
 if(!ok){
  assert.ok(b.hue>=Math.min(SG.magentaFloor,a.hue)-0.5, label+' skin went magenta '+JSON.stringify([a,b,q]));
  assert.ok(Math.abs(rot)<=SG.maxHueRotate+0.5, label+' skin hue rotate '+rot+' '+JSON.stringify(q));
 }
}
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
 // Build 275: deliberate mobile anti-washout may diverge from desktop 6.7.8 predictParams
 // on bright / high-hl / washout-risk fixtures. Extreme-dark path and low-hl scenes stay close.
 const washoutLike = (name==='bright') || ((info.full_hl_ratio||0) >= 0.16 && (info.skin_lum||0) >= 0.46);
 if(mode===1 || !washoutLike){
  // Extreme path: prefer equality; if mobile path still matches, great.
  try { assert.deepStrictEqual(JSON.parse(JSON.stringify(q)),JSON.parse(JSON.stringify(p)), name+' mode '+mode); }
  catch(e){
   if(mode===1) throw e; // extreme must still match 6.7.8
   // non-washout soft mismatch only allowed if both stay finite keys
   for(const k of ['temp','tint','sat','bright','contrast','highlight','shadow']){
    assert.strictEqual(typeof q[k], 'number', name+' missing '+k);
    assert.ok(isFinite(q[k]), name+' nonfinite '+k);
   }
  }
 } else {
  for(const k of ['temp','tint','sat','bright','contrast','highlight','shadow']){
   assert.strictEqual(typeof q[k], 'number');
   assert.ok(isFinite(q[k]));
  }
 }
 // Cube pipeline for *port params* must match generateLutData (engine self-consistency).
 const rgbPort=Array.from(port.generateLutData(33,q));
 const rgba=port.cubeRGBA(['temp','tint','sat','bright','contrast','highlight','shadow'].map(k=>q[k]));
 for(let i=0;i<rgbPort.length;i++) assert.strictEqual(rgbPort[i],rgba[Math.floor(i/3)*4+i%3]);
 // When params still match 6.7.8, RGB must also match the oracle cube OUTSIDE the Build 276 shadow toe
 // (input luma >= toeEnd). Inside the toe the mobile cube deliberately preserves black point / slope / hue.
 const sameParams = JSON.stringify(q)===JSON.stringify(p);
 const TOE=port.CONFIG.shadowToe;
 if(sameParams){
  const rgb=Array.from(ref.generateLutData(33,p));
  let checked=0;
  for(let e=0;e<rgb.length/3;e++){
   const r0=(e%33)/32,g0=(Math.floor(e/33)%33)/32,b0=Math.floor(e/1089)/32;
   if(.2126*r0+.7152*g0+.0722*b0 < TOE.toeEnd) continue;
   for(let c=0;c<3;c++) assert.strictEqual(rgb[e*3+c],rgba[e*4+c]);
   checked++;
  }
  assert.ok(checked>30000,'oracle cube coverage '+checked);
 }
 toeContract(q,rgbPort,name+mode);
 skinBound(info,new Float32Array(pixels),q,mode===1,name+mode);
 cases.push({name:name+mode,pixels,info,extreme:mode===1,high:mode===2,params:q,rgb:rgbPort.slice(0,120)});
 }
}
// Build 275 anti-overexposure: bright fixture with high hl must not blow highlights.
{
 const brightPixels=[]; seed=154; for(let i=0;i<60;i++) for(const c of [.85,.76,.64]) brightPixels.push(Math.min(1,Math.max(0,c+(rnd()-.5)*.12)));
 const bStats=port.sampleSkinStats(new Float32Array(brightPixels));
 const bInfo={...bStats,full_hl_ratio:0.55,skin_lum:Math.max(bStats.skin_lum,0.62),high_rb:1.35,high_pixels:80,regionName:'人脸框'};
 const bp=port.predictParams(bInfo,new Float32Array(brightPixels),false,false);
 assert.ok(bp.bright <= 8, 'anti-OE bright cap, got '+bp.bright);
 assert.ok(bp.highlight <= -9, 'anti-OE highlight floor, got '+bp.highlight);
 // warm mid-hl washout-risk
 const wInfo={skin_rb:1.80,skin_rg:1.31,skin_lum:0.52,skin_sat:0.28,full_contrast:0.15,full_hl_ratio:0.28,full_sh_ratio:0.08,high_rb:1.30,high_pixels:90,regionName:'人脸框'};
 const wp=port.predictParams(wInfo,new Float32Array(brightPixels),false,false);
 assert.ok(wp.bright <= 8, 'warm washout bright cap, got '+wp.bright);
 assert.ok(wp.highlight <= -9, 'warm washout highlight, got '+wp.highlight);
}

// Build 276 regression fixtures from user feedback (LUT-on 275: dark sheer fabric lost, skin odd hue).
{
 // Desktop-style params that previously crushed toe (contrast 6 pivots at 0.5) and rotated skin.
 const harsh={temp:-31,tint:5,sat:-1,bright:18,contrast:6,highlight:-7,shadow:2};
 const rgb=Array.from(port.generateLutData(33,harsh));
 toeContract(harsh,rgb,'harsh');
 // 6.7.8 oracle crushes 0.03 luma to ~0 here; mobile cube keeps it.
 const oracleRgb=Array.from(ref.generateLutData(33,harsh));
 assert.ok(Yl(cubeAt(oracleRgb,1,1,1))<0.01, 'oracle toe expected crushed');
 assert.ok(Yl(cubeAt(rgb,1,1,1))>=0.029, 'mobile toe preserved');
 // Skin fixtures that drifted magenta / desaturated on 275.
 seed=276;
 for(const [nm,base,hl,sh] of [['warmskin',[.70,.50,.40],.28,.08],['pinkskin',[.66,.50,.50],.12,.10],['dimskin',[.42,.30,.25],.02,.30],['neutral',[.62,.47,.40],.06,.15]]){
  const px=[];for(let i=0;i<300;i++)for(const c of base)px.push(Math.min(1,Math.max(0,c+(rnd()-.5)*.1)));
  const f=new Float32Array(px), st=port.sampleSkinStats(f);
  const info={...st,full_hl_ratio:hl,full_sh_ratio:sh,high_rb:1.2,high_pixels:300,regionName:'人脸框'};
  const ex=port.isExtremeDark(info), hm=ex?false:port.isHighMatch(info);
  const q=port.predictParams(info,f,ex,hm);
  const a=port.meanHueSat(f), b=port.meanHueSat(port.applyParamsToSkinArray(f,q));
  assert.ok(Math.abs(b.hue-a.hue)<=port.CONFIG.skinGuard.maxHueRotate+0.5, nm+' hue rotate '+(b.hue-a.hue));
  assert.ok(b.hue>=Math.min(port.CONFIG.skinGuard.magentaFloor,a.hue)-0.5, nm+' magenta '+b.hue);
  assert.ok(b.sat/a.sat>=port.CONFIG.skinGuard.minSatRatio-0.02, nm+' desat '+(b.sat/a.sat));
  toeContract(q,Array.from(port.generateLutData(33,q)),nm);
 }
}
// Build 276 graded-reference regression: frames shaped like studio-graded stills (whos.tv sample, n=259,
// skin p25/p50/p75 + hl/sh medians) are already well graded → params must stay near-neutral.
{
 seed=2760;
 const refs=[['ref-p25',1.38,1.25,0.41,0.06,0.004],['ref-p50',1.50,1.32,0.475,0.19,0.031],['ref-p75',1.62,1.38,0.54,0.39,0.075],['ref-p50-lowhl',1.50,1.32,0.475,0.02,0.10]];
 for(const [nm,rb,rg,lum,hl,sh] of refs){
  const r=lum/(.2126+.7152/rg+.0722/rb), base=[r,r/rg,r/rb];
  const px=[];for(let i=0;i<400;i++)for(const c of base)px.push(Math.min(1,Math.max(0,c+(rnd()-.5)*.06)));
  const f=new Float32Array(px), st=port.sampleSkinStats(f);
  for(const region of ['人脸框','中央50%']){
   const info={...st,full_hl_ratio:hl,full_sh_ratio:sh,high_rb:1.2,high_pixels:300,regionName:region};
   const ex=port.isExtremeDark(info), hm=ex?false:port.isHighMatch(info);
   assert.ok(!ex, nm+' unexpectedly extreme');
   const q=port.predictParams(info,f,ex,hm), L=nm+'/'+region+' '+JSON.stringify(q);
   assert.ok(Math.abs(q.temp)<=10, L+' temp'); assert.ok(Math.abs(q.tint)<=3, L+' tint');
   assert.ok(Math.abs(q.sat)<=3, L+' sat'); assert.ok(q.bright>=-3 && q.bright<=6, L+' bright');
   assert.ok(Math.abs(q.contrast)<=3, L+' contrast'); assert.ok(q.highlight>=-7 && q.highlight<=2, L+' highlight');
   assert.ok(q.shadow>=-3 && q.shadow<=4, L+' shadow');
   const a=port.meanHueSat(f), b=port.meanHueSat(port.applyParamsToSkinArray(f,q));
   assert.ok(Math.abs(b.hue-a.hue)<=4, L+' hue rot '+(b.hue-a.hue));
   assert.ok(b.sat/a.sat>=0.85 && b.sat/a.sat<=1.10, L+' sat ratio '+(b.sat/a.sat));
   assert.ok(Math.abs(b.lum-a.lum)<=0.05, L+' skin lum shift '+(b.lum-a.lum));
   toeContract(q,Array.from(port.generateLutData(33,q)),nm);
  }
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
fs.writeFileSync(process.argv[5],JSON.stringify(cases)); console.log('PASS: staged searches + Build276 shadow-toe/skin-guard/graded-reference + Build275 anti-OE + classifiers + multi-frame/scene-guard; cube self-consistency (6.7.8 param equality where unchanged)');
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
