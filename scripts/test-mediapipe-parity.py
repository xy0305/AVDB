from pathlib import Path
import subprocess,tempfile,sys
r=Path(__file__).resolve().parents[1]
s=(r/'THIRD_PARTY/lut-v6.7.5.txt').read_text()
a=s.index('    const CONFIG = {');b=s.index('    function getOrCreateOverlayRoot')
c=s.index('    const KR =');d=s.index('    // ============================================================\n    // 四、MediaPipe 加载')
e=s.index('    function computeGlobalHlRatio');f=s.index('    function captureFaceSkinPixels')
g=s.index('        let sampleRegion;',f);h=s.index('    async function captureSingleFrame',g)
oracle='var console={log(){}};'+s[a:b]+s[c:d]+s[e:f]+'function sampleFrame(data,aw,ah,faceBox){const faceDetected=!!faceBox;const full_hl_ratio_global=computeGlobalHlRatio(data,CONFIG.globalHlSampleStep);'+s[g:h]
js=r'''
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const a=vm.createContext({}),b=vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),a);vm.runInContext(fs.readFileSync(process.argv[3],'utf8'),b);
const ref=vm.runInContext('({sampleFrame,computeRegionCrRange})',b),port=a.OriginalLUT;
let seed=155;function rand(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed>>>24;}
function norm(x){return JSON.parse(JSON.stringify(x,(k,v)=>ArrayBuffer.isView(v)?Array.from(v):v));}
for(const [w,h] of [[640,359],[359,640],[64,33],[1,1]]) {
 const data=new Uint8ClampedArray(w*h*4);
 for(let i=0;i<data.length;i+=4){data[i]=rand();data[i+1]=rand();data[i+2]=rand();data[i+3]=255;}
 for(const box of [null,{x1:0,y1:0,x2:w,y2:h},{x1:7,y1:9,x2:w-5,y2:h-3},{x1:0,y1:0,x2:0,y2:0}]){
  assert.deepStrictEqual(norm(port.sampleFrame(data,w,h,box)),norm(ref.sampleFrame(data,w,h,box)));
 }
}
console.log('PASS 16 complete sampleFrame outputs vs independent original oracle; dynamicCr and all returned pixel arrays exact');
const cases=[[],[[[.101,.201],[.899,.799]],[[0,0],[1,1]]],[[[-.2,-.1],[1.2,1.1]]],[[[.3,.3],[.3,.3]]],[[[.5,.5],[.50000001,.50000001]]]];
const fixtures=cases.map(faces=>{let box=null;if(faces.length){let x1=Infinity,y1=Infinity,x2=-Infinity,y2=-Infinity;for(const [x,y] of faces[0]){x1=Math.min(x1,x);y1=Math.min(y1,y);x2=Math.max(x2,x);y2=Math.max(y2,y);}const cx=(x1+x2)/2,cy=(y1+y2)/2,hw=(x2-x1)/2*1,hh=(y2-y1)/2*1;box={x1:Math.max(0,Math.floor((cx-hw)*640)),y1:Math.max(0,Math.floor((cy-hh)*359)),x2:Math.min(640,Math.ceil((cx+hw)*640)),y2:Math.min(359,Math.ceil((cy+hh)*359))};}return {faces,box};});
fs.writeFileSync(process.argv[4],JSON.stringify(fixtures));
'''
with tempfile.TemporaryDirectory() as tmp:
 t=Path(tmp);(t/'oracle.js').write_text(oracle);(t/'test.js').write_text(js)
 subprocess.run(['node',str(t/'test.js'),str(r/'AVDB/Resources/OriginalLUT.js'),str(t/'oracle.js'),str(t/'fixtures.json')],check=True)
 if sys.platform!='darwin':
  print('Native Swift ROI test requires macOS; not claimed locally.');sys.exit(0)
 source=(r/'AVDB/Views/Player/NativeLUT.swift').read_text();a=source.index('enum OriginalLandmarkGeometry');b=source.index('/// Official Tasks Vision',a)
 swift='import Foundation\n'+source[a:b]+'''\nlet fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
for f in fixtures {
 let box = OriginalLandmarkGeometry.region(faces: f["faces"] as! [[[Double]]], width: 640, height: 359)
 let expected = f["box"] as? [String: Int]
 precondition(box == expected, "Native ROI differs from original JS oracle")
}
print("PASS Swift actual ROI function: first-face selection, min/max, fractional rounding, clipping, empty and degenerate")
'''
 (t/'test.swift').write_text(swift);subprocess.run(['swift',str(t/'test.swift'),str(t/'fixtures.json')],check=True)
