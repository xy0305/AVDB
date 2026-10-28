import SwiftUI
import AVFoundation
import CoreImage
import JavaScriptCore

// The fixture never constructs MediaPipe. Only this boundary and KSAVPlayer are stubs.
final class KSAVPlayer { let player: AVPlayer; init(_ player: AVPlayer) { self.player = player } }
final class OriginalFaceLandmarker {
    static let shared = OriginalFaceLandmarker()
    func region(image: CGImage) -> (box: [String:Int]?, description: String) { (nil, "neutral fixture; inference NOT RUN") }
}
struct FixtureFailure: Error { let message: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FixtureFailure(message: message) }
}
@main struct LUT83Fixture: App {
    var body: some Scene { WindowGroup { Text("LUT83 neutral local test").task { await run() } } }
    @MainActor func run() async {
        var checks = [String]()
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        do {
            let zero = LUTParameters()
            let cube = NativeLUT.cube(zero)!
            try require(cube.count == 33*33*33*4*4, "cube size")
            try require(NativeLUT.cube(LUTParameters(values: [Double.nan])) == nil, "invalid guard")
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ci = CIContext(options: [.workingColorSpace: cs])
            let samples: [[Float]] = [[0,0,0],[1,1,1],[0.5,0.5,0.5],[1,0,0],[0,1,0],[0,0,1],[1,1,0.875]]
            for rgb in samples {
                let values = rgb + [1]
                let image = values.withUnsafeBytes { CIImage(bitmapData: Data($0), bytesPerRow:16, size:CGSize(width:1,height:1), format:.RGBAf, colorSpace:cs) }
                let mapped = CIFilter(name:"CIColorCubeWithColorSpace", parameters:["inputCubeDimension":33,"inputCubeData":cube,"inputColorSpace":cs,kCIInputImageKey:image])!.outputImage!
                var result = [Float](repeating:0,count:4)
                result.withUnsafeMutableBytes { ci.render(mapped,toBitmap:$0.baseAddress!,rowBytes:16,bounds:image.extent,format:.RGBAf,colorSpace:cs) }
                for i in 0..<4 { try require(abs(result[i]-values[i]) < 0.002, "simulator CI identity") }
            }
            checks.append("production NativeLUT JSContext cube, invalid guard and CoreImage identity/RGB boundary rendering")
            // Generate a tiny local neutral SDR file. No URLSession, network or source adapter.
            let movie = output.deletingLastPathComponent().appendingPathComponent("neutral.mov")
            try? FileManager.default.removeItem(at:movie)
            let writer = try AVAssetWriter(outputURL:movie,fileType:.mov)
            let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:48])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:48])
            writer.add(input);writer.startWriting();writer.startSession(atSourceTime:.zero)
            for frame in 0..<6 {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:10_000_000) }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)
                CVPixelBufferLockBaseAddress(buffer!,[])
                memset(CVPixelBufferGetBaseAddress(buffer!),128,CVPixelBufferGetDataSize(buffer!))
                CVPixelBufferUnlockBaseAddress(buffer!,[])
                try require(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(frame),timescale:6)),"append local frame")
            }
            input.markAsFinished();await writer.finishWriting()
            try require(writer.status == .completed,"local asset writer")
            let bridge = KSAVPlayer(AVPlayer(url:movie))
            let controller = NativeLUTController()
            controller.tick(bridge)
            for _ in 0..<100 {
                if controller.supported { break }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            try require(controller.supported,"local SDR format gate: \(controller.status)")
            controller.enabled = true;controller.parameters = zero
            let before = NativeLUT.fixtureBakeCount
            controller.apply();try await Task.sleep(nanoseconds:1_500_000_000)
            try require(controller.fixtureCache == zero && bridge.player.currentItem!.videoComposition != nil,"first cache publication")
            try require(NativeLUT.fixtureBakeCount == before+1,"first bake")
            controller.strength=0.5;controller.apply();try await Task.sleep(nanoseconds:400_000_000)
            try require(NativeLUT.fixtureBakeCount == before+1,"exact cache reuse")
            controller.parameters.values[0]=5;controller.apply();try await Task.sleep(nanoseconds:1_500_000_000)
            try require(controller.fixtureCache == controller.parameters,"changed key refresh")
            try require(NativeLUT.fixtureBakeCount == before+2,"changed params require bake")
            controller.parameters.values[0]=10;controller.apply();controller.reset()
            try await Task.sleep(nanoseconds:500_000_000)
            try require(controller.fixtureCache == nil && bridge.player.currentItem!.videoComposition == nil,"reset invalidates pending publish/cache")
            controller.enabled=true;controller.apply();controller.detach()
            try await Task.sleep(nanoseconds:500_000_000)
            try require(!controller.supported && controller.fixtureCache == nil && bridge.player.currentItem!.videoComposition == nil,"detach invalidates pending publish/cache")
            checks.append("production controller: local SDR format gate, exact-key cube reuse, changed-key bake, reset/detach stale publication guards")
            let data = try JSONSerialization.data(withJSONObject:["passed":true,"checks":checks,"boundaries":"Production controller copied verbatim except import/face and KSPlayer boundary stubs and bake counter instrumentation. MediaPipe/model inference, model GPU threading and physical device FPS NOT RUN. Local synthetic media only."],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:output)
        } catch {
            let data = try! JSONSerialization.data(withJSONObject:["passed":false,"error":String(describing:error),"checks":checks],options:.prettyPrinted)
            try! data.write(to:output)
        }
    }
}
