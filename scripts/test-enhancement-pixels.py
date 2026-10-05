from pathlib import Path
import subprocess,sys,tempfile
if sys.platform != 'darwin':
    print('SKIP CoreImage enhancement pixels: macOS required'); sys.exit(0)
source=Path('AVDB/Resources/Enhancement.metal')
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    subprocess.run(['xcrun','-sdk','macosx','metal','-fcikernel','-c',str(source),'-o',str(root/'k.air')],check=True)
    subprocess.run(['xcrun','-sdk','macosx','metallib','-cikernel',str(root/'k.air'),'-o',str(root/'k.metallib')],check=True)
    swift=r'''import Foundation
import CoreImage
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: cs])
let kernel = try CIKernel(functionName: "avdbDeband", fromMetalLibraryData: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let w=64, h=16
func image(_ mode:Int) -> CIImage {
 var values=[Float]()
 for _ in 0..<h { for x in 0..<w {
  let v:Float = mode == 0 ? 0.4 : mode == 1 ? 0.4 + Float(x/4)*0.0006 : (x < 32 ? 0.2 : 0.8)
  values += [v,v,v,1]
 } }
 return values.withUnsafeBytes { CIImage(bitmapData: Data($0), bytesPerRow:w*16, size:CGSize(width:w,height:h), format:.RGBAf, colorSpace:cs) }.transformed(by:CGAffineTransform(translationX:12,y:5))
}
func pixels(_ i:CIImage)->[Float] {
 var out=[Float](repeating:0,count:w*h*4)
 context.render(i,toBitmap:&out,rowBytes:w*16,bounds:i.extent,format:.RGBAf,colorSpace:cs)
 return out
}
func deband(_ i:CIImage)->CIImage {
 let n=i.matchedFromWorkingSpace(to:cs)
 return kernel.apply(extent:i.extent,roiCallback:{ _,r in r.insetBy(dx:-8,dy:-8) },arguments:[n.clampedToExtent(),0.002,8.0])!.matchedToWorkingSpace(from:cs).cropped(to:i.extent)
}
for mode in 0...2 {
 let input=image(mode), result=deband(input)
 precondition(result.extent == input.extent)
 let a=pixels(input), b=pixels(result), c=pixels(deband(input))
 precondition(b == c,"determinism")
 if mode != 1 { precondition(zip(a,b).allSatisfy { abs($0-$1)<0.00001 },"constant/edge identity") }
 else { precondition(zip(a,b).contains { abs($0-$1)>0.00001 },"gradient band changed") }
 for n in stride(from:3,to:b.count,by:4) { precondition(abs(b[n]-1)<0.00001) }
}
let source=image(2), target=image(0)
for amount in [0.0,0.5,1.0] {
 let blended=target.applyingFilter("CIDissolveTransition",parameters:["inputTargetImage":source,"inputTime":1-amount]).cropped(to:source.extent)
 let out=pixels(blended), a=pixels(source), b=pixels(target)
 for n in 0..<out.count { precondition(abs(Double(out[n])-(Double(a[n])*(1-amount)+Double(b[n])*amount))<0.0001) }
}
let neutral=image(0)
for sharp in [0.0,0.1,0.2] {
 let output=neutral.clampedToExtent().applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:sharp]).cropped(to:neutral.extent)
 precondition(zip(pixels(neutral),pixels(output)).allSatisfy { abs($0-$1)<0.0001 })
}
print("PASS actual Metal/CoreImage synthetic SDR: constant identity, band-gradient changes, hard-edge preservation, deterministic output, alpha and nonzero extent; image blend endpoints/midpoint; neutral sharpen 0/0.1/0.2. Not device benchmark or decoder metadata test.")
'''
    (root/'test.swift').write_text(swift)
    subprocess.run(['swift',str(root/'test.swift'),str(root/'k.metallib')],check=True)
