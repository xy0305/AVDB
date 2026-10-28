const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(process.argv[2],'utf8');vm.runInThisContext(source);
const fixtures=JSON.parse(fs.readFileSync(__dirname+'/fixtures83-full.json','utf8'));
let reports=[];
for(const f of fixtures){
 let p=Desktop83.predict(f.a,f.info);assert.deepStrictEqual(p.values,f.params);
 const colors=[[0,0,0],[1,1,1],[.3,.5,.7],[.8,.9,.7]];
 colors.forEach((rgb,i)=>Desktop83.pixel(rgb,p.values,false).forEach((v,c)=>assert(Math.abs(v-f.rgb[i][c])<1e-12)));
 reports.push({stage:p.stage,params:p.values});
}
// Exact desktop zero identity; no global .92 clipping for unaffected whites.
assert.deepStrictEqual(Desktop83.pixel([1,1,1],[0,0,0,0,0,0,0],false),[1,1,1]);
for(const size of [33,65]){
 const start=Date.now(),data=Desktop83.cubeRGBA([0,0,0,0,0,0,0],size);assert.equal(data.length,size**3*4);
 for(let b=0;b<size;b+=size-1)for(let g=0;g<size;g+=size-1)for(let r=0;r<size;r+=size-1){let i=((b*size+g)*size+r)*4;assert.deepStrictEqual(data.slice(i,i+4),[r/(size-1),g/(size-1),b/(size-1),1]);}
 reports.push({size,ms:Date.now()-start,notDeviceFPS:true});
}
assert.equal(Desktop83.analyze([]),null);
const sample=fixtures[0].a;
const a=Desktop83.analyze(Array(24).fill(sample));assert.equal(a.frames,24);assert.equal(a.pixels.length,1440);
assert(Desktop83.select(Array(400).fill(0),10,10,null).length===0);
console.log(JSON.stringify({passed:true,oracleFixtures:fixtures.length,reports},null,2));
