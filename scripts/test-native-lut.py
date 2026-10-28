from pathlib import Path
import subprocess, tempfile, json, sys
root=Path(__file__).resolve().parents[1]
engine=root/'AVDB/Resources/OriginalLUT.js'
node_test=root/'scripts/test-lut83.js'
with tempfile.TemporaryDirectory() as directory:
    tmp=Path(directory)
    subprocess.run(['node',str(node_test),str(engine),str(tmp/'fixtures.json')],check=True)
    if sys.platform!='darwin':
        print('NOT RUN: JavaScriptCore/CoreImage native tests require macOS; no iOS performance claim.')
        sys.exit(0)
    swift=r'''
import Foundation
import JavaScriptCore
import CoreImage
import CoreGraphics
let context = JSContext()!
context.evaluateScript(try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
precondition(context.exception == nil)
let api = context.objectForKeyedSubscript("OriginalLUT")!
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let fixtures = try JSONSerialization.jsonObject(with: data) as! [[String:Any]]
var timings: [Double] = []
for c in fixtures {
    context.setObject(c["pixels"], forKeyedSubscript: "inputPixels" as NSString)
    let pixels = context.evaluateScript("new Float32Array(inputPixels)")!
    let p = api.objectForKeyedSubscript("predictParams")!.call(withArguments: [c["info"]!,pixels,c["extreme"]!,false])!
    precondition(context.exception == nil)
    let expected = c["params"] as! [String:NSNumber]
    let actual = p.toDictionary() as! [String:NSNumber]
    precondition(Set(expected.keys) == Set(actual.keys))
    for (key,value) in expected { precondition(abs(value.doubleValue-actual[key]!.doubleValue)<1e-7) }
    let start = ProcessInfo.processInfo.systemUptime
    let cube = api.objectForKeyedSubscript("cubeRGBA")!.call(withArguments:[c["values"]!])!.toArray() as! [NSNumber]
    timings.append((ProcessInfo.processInfo.systemUptime-start)*1000)
    let wanted = c["rgba"] as! [NSNumber]
    for i in wanted.indices { precondition(abs(cube[i].doubleValue-wanted[i].doubleValue)<1e-7) }
}
let numbers = api.objectForKeyedSubscript("cubeRGBA")!.call(withArguments:[[0,0,0,0,0,0,0]])!.toArray() as! [NSNumber]
let floats = numbers.map { $0.floatValue }
let cubeData = floats.withUnsafeBytes { Data($0) }
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: cs])
func render(_ image: CIImage) -> [Float] {
    var result = [Float](repeating:0,count:4)
    result.withUnsafeMutableBytes { bytes in
        ci.render(image,toBitmap:bytes.baseAddress!,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:cs)
    }
    return result
}
let samples: [[Float]] = [[0,0,0],[1,1,1],[0.5,0.5,0.5],[1,0,0],[0,1,0],[0,0,1],[1,1,0.875]]
for rgb in samples {
    var input = rgb + [1]
    let source = input.withUnsafeBytes { CIImage(bitmapData:Data($0),bytesPerRow:16,size:CGSize(width:1,height:1),format:.RGBAf,colorSpace:cs) }
    let mapped = CIFilter(name:"CIColorCubeWithColorSpace",parameters:["inputCubeDimension":33,"inputCubeData":cubeData,"inputColorSpace":cs,kCIInputImageKey:source])!.outputImage!
    let raw = render(source), out = render(mapped)
    for i in 0..<4 { precondition(abs(raw[i]-out[i])<0.002,"CI identity/color-space mismatch") }
    let zero = mapped.applyingFilter("CIDissolveTransition", parameters:["inputTargetImage":source,"inputTime":1.0])
    let bypass = render(zero)
    for i in 0..<4 { precondition(abs(raw[i]-bypass[i])<0.002,"strength zero mismatch") }
}
print("PASS: native JavaScriptCore parameter/cube parity; CoreImage identity/RGB boundaries/zero-strength dissolve")
print("Native macOS JavaScriptCore cube baking milliseconds: \(timings) (not iOS FPS)")
'''
    (tmp/'main.swift').write_text(swift)
    subprocess.run(['swift',str(tmp/'main.swift'),str(engine),str(tmp/'fixtures.json')],check=True)
