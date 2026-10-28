import SwiftUI
import AVFoundation
import CoreImage
// Neutral fixture adapter only: production simulator compile excludes KSPlayer import.
final class KSAVPlayer { var player = AVPlayer() }
@main struct RestoreLUTNeutralApp: App {
    var body: some Scene { WindowGroup { FixtureView() } }
}
struct FixtureView: View {
    @StateObject private var model = NativeLUTController()
    var body: some View {
        NativeLUTPanel(model: model)
            .task {
                do {
                    let size = 33*33*33*4*MemoryLayout<Float>.size
                    guard let cube = NativeLUT.cube(LUTParameters()), cube.count == size else { throw NSError(domain:"cube",code:1) }
                    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
                    let context = CIContext(options: [.workingColorSpace: cs])
                    let original = CIImage(color: CIColor(red:0.7,green:0.6,blue:0.5)).cropped(to: CGRect(x:0,y:0,width:16,height:16))
                    guard let mapped = CIFilter(name:"CIColorCubeWithColorSpace", parameters:["inputCubeDimension":33,"inputCubeData":cube,"inputColorSpace":cs,kCIInputImageKey:original])?.outputImage else { throw NSError(domain:"filter",code:2) }
                    var pixels=[Float](repeating:0,count:16*16*4)
                    context.render(mapped,toBitmap:&pixels,rowBytes:16*16,bounds:original.extent,format:.RGBAf,colorSpace:cs)
                    precondition(pixels.allSatisfy { $0.isFinite })
                    let reveal = LUTRevealState.composite(original:original,filtered:mapped,originalFraction:0.5)
                    precondition(reveal.extent == original.extent)
                    model.strength = 0.5; model.comparison = true; model.updateComparison(); model.reset()
                    let result:[String:Any] = ["passed":true,"cubeBytes":cube.count,"finiteCoreImagePixels":true,"productionOldPanelRendered":true,"splitExtentPreserved":true,"realFaceModelInference":false,"onlineMedia":false]
                    let data = try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted)
                    let url = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.json")
                    try data.write(to:url)
                } catch { print("NEUTRAL FIXTURE FAILED",error) }
            }
    }
}
