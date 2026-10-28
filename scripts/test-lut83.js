const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {performance}=require('perf_hooks');
const context=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),context);
const api=context.OriginalLUT,zero=[0,0,0,0,0,0,0],keys=['temp','tint','sat','bright','contrast','highlight','shadow'];
const checks=[];function test(name,fn){fn();checks.push(name);}
let fixtures=[];
test('33^3 identity, red-fastest full lattice including every boundary',()=>{
 const cube=api.cubeRGBA(zero); assert.equal(cube.length,33*33*33*4);
 for(let b=0;b<33;b++)for(let g=0;g<33;g++)for(let r=0;r<33;r++){
 const i=((b*33+g)*33+r)*4;assert.equal(cube[i],r/32);assert.equal(cube[i+1],g/32);assert.equal(cube[i+2],b/32);assert.equal(cube[i+3],1);}
});
test('invalid inputs and malformed boxes never introduce NaN',()=>{
 for(const v of [[],[NaN,...zero.slice(1)],[Infinity,...zero.slice(1)],[null,...zero.slice(1)]])assert.equal(api.cubeRGBA(v),null);
 assert.equal(api.analyzeFrame([],100,100,null),null);assert.equal(api.analyzeFrame([],NaN,1,null),null);
 assert.equal(api.analyzeFrame(new Array(16).fill(120),2,2,{x1:NaN,y1:0,x2:2,y2:2}),null);
});
test('parameter extremes finite bounded RGBA',()=>{
 for(const values of [[-50,-50,-50,-50,-50,-50,-50],[50,50,50,50,50,50,50],[1e100,-1e100,0,0,0,0,0]]){
 const cube=api.cubeRGBA(values);for(let i=0;i<cube.length;i++)assert(Number.isFinite(cube[i])&&cube[i]>=0&&cube[i]<=1);
 }
});
test('neutral saturation and brightness do not introduce tint',()=>{
 for(const values of [[0,0,50,0,0,0,0],[0,0,-50,10,2,-5,5]]){
 const cube=api.cubeRGBA(values);for(let n=0;n<33;n++){const i=((n*33+n)*33+n)*4;assert(Math.abs(cube[i]-cube[i+1])<1e-7);assert(Math.abs(cube[i+1]-cube[i+2])<1e-7);}
 }
});
test('v8.3 0.82 saturation response and reduced highlight temperature cast',()=>{
 const p={temp:0,tint:0,sat:10,bright:0,contrast:0,highlight:0,shadow:0};const rgb=[.6,.4,.3],gray=.2126*.6+.7152*.4+.0722*.3;
 const out=api.applyParamsToSkinArray(rgb,p);for(let i=0;i<3;i++)assert(Math.abs(out[i]-(gray+1.164*(rgb[i]-gray)))<1e-7);
 const t={...p,sat:0,temp:-30};const a=api.applyParamsToSkinArray([.5,.5,.5],t),b=api.applyParamsToSkinArray([1,1,1],t);assert(Math.abs(b[0]-b[2])<Math.abs(a[0]-a[2])*.3);
});
function frame(rgb,w=64,h=48){const out=[];for(let i=0;i<w*h;i++)out.push(...rgb,255);return out;}
test('no face uses full image, off-center valid skin participates',()=>{
 const w=96,h=64,bytes=frame([100,100,100],w,h);
 for(let y=0;y<h;y++)for(let x=0;x<20;x++){let i=(y*w+x)*4;bytes[i]=145;bytes[i+1]=120;bytes[i+2]=110;}
 const result=api.analyzeFrame(bytes,w,h,null);assert(result);assert.equal(result.info.regionName,'全画面回退');
});
test('naturally matching skin is protected rather than forced cool',()=>{
 const bytes=frame([145,120,110]);const result=api.analyzeFrame(bytes,64,48,null);assert(result);assert.equal(result.stage,'肤色保护');for(const k of keys)assert.equal(result.params[k],0);
});
test('darkness gate distinguishes yellow medium-dark and extreme darkness',()=>{
 const base={skin_rb:1.4,skin_lum:.2,full_sh_ratio:.6,full_hl_ratio:.05};assert(api.isExtremeDark(base));assert(!api.isExtremeDark({...base,skin_rb:1.7}));assert(!api.isExtremeDark({...base,skin_lum:.25}));assert(!api.isExtremeDark({...base,full_hl_ratio:.11}));
});
test('final brightness check applies after parameter balancing, deterministic search',()=>{
 let seed=267;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;}
 for(const base of [[.6,.45,.35],[.55,.42,.32],[.18,.15,.13],[.8,.65,.5],[.7,.45,.25]]){
 const pixels=[];for(let i=0;i<180;i++)for(const c of base)pixels.push(Math.max(0,Math.min(1,c+(rnd()-.5)*.08)));
 const info={...api.sampleSkinStats(pixels),high_rb:1.1,high_pixels:0,regionName:'人脸框'};const extreme=api.isExtremeDark(info);const p=api.predictParams(info,pixels,extreme,false),q=api.predictParams(info,pixels,extreme,false);
 assert.equal(JSON.stringify(p),JSON.stringify(q));assert(p.bright<=(extreme?35:10));
 if(info.skin_lum>=.35&&info.skin_lum<=.54){const after=api.sampleSkinStats(api.applyParamsToSkinArray(pixels,p));assert(after.skin_lum>=info.skin_lum-.0051);}
 const values=keys.map(k=>p[k]),cube=api.cubeRGBA(values);fixtures.push({pixels,info,extreme,params:p,values,rgb:api.generateLutData(33,p).slice(0,120),rgba:Array.from(cube.slice(0,160))});
 }
});
const samples=[];for(let i=0;i<5;i++){const t=performance.now();api.cubeRGBA([0,0,3,4,-1,-2,2]);samples.push(performance.now()-t);}
const report={checks,passed:checks.length,platform:process.platform,arch:process.arch,engine:process.version,cubeBakeMilliseconds:samples,benchmarkNote:'Node wall-clock only; not iOS FPS or GPU performance'};
if(process.argv[3])fs.writeFileSync(process.argv[3],JSON.stringify(fixtures));
console.log(JSON.stringify(report,null,2));
