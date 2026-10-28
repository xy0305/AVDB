import SwiftUI
import AVFoundation
import CoreImage
import JavaScriptCore

// Only KSPlayer transport is stubbed. Production MediaPipe GPU/VIDEO is invoked on its dedicated thread.
final class KSAVPlayer { let player: AVPlayer; init(_ player: AVPlayer) { self.player = player } }
struct FixtureFailure: Error { let message: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FixtureFailure(message: message) }
}
@main struct LUT83Fixture: App {
    @StateObject private var panelModel = NativeLUTController()
    var body: some Scene { WindowGroup { NativeLUTPanel(model: panelModel).task { await run() } } }
    @MainActor func run() async {
        var checks = [String]()
        var inferenceSummary = "NOT RUN"
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
            // Actual production interchange, parser denial paths and dedicated-thread inference.
            let archive = LUTArchive(size:33,rgba:cube,domainMin:[-0.1,0,0],domainMax:[1.1,1,1])
            let roundtrip = try LUTArchive.parse(archive.text())
            try require(roundtrip == archive,"cube roundtrip with real domain")
            for bad in ["LUT_3D_SIZE 66", "LUT_3D_SIZE 2\nNaN 0 0", "LUT_3D_SIZE 2\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0", "LUT_1D_SIZE 2"] {
                do { _ = try LUTArchive.parse(bad); throw FixtureFailure(message:"accepted invalid cube") }
                catch is LUTError { }
            }
            let skin = CIImage(color:CIColor(red:0.6,green:0.45,blue:0.4)).cropped(to:CGRect(x:0,y:0,width:64,height:48))
            let skinCG = ci.createCGImage(skin,from:skin.extent,format:.RGBA8,colorSpace:cs)!
            let full = await Task.detached { NativeLUT.fullAnalyze([LUTFrame(image:skinCG)],faithful:true) }.value
            try require(full != nil,"full numeric pipeline with real MediaPipe attempt")
            inferenceSummary = full!.summary
            let faithfulCube = NativeLUT.bake(full!.parameters,faithful:true)!
            try require(faithfulCube.count == cube.count,"faithful cube")
            let zero65 = NativeLUT.bake(zero,faithful:true,size:65)!
            try require(zero65.count == 65*65*65*16,"65 cube")
            checks.append("CUBE roundtrip/domain; malformed/NaN/unsupported rejection; real production GPU VIDEO model attempt; full prediction; 65 cube")
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
                let raw = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to:UInt8.self)
                for y in 0..<48 { for x in 0..<64 { let i=y*CVPixelBufferGetBytesPerRow(buffer!)+x*4;raw[i]=102;raw[i+1]=115;raw[i+2]=153;raw[i+3]=255 } }
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
            // Bounded AVAssetImageGenerator real local multi-time sampling and cancellation.
            controller.tick(bridge)
            for _ in 0..<100 { if controller.supported { break }; try await Task.sleep(nanoseconds:100_000_000) }
            controller.faithful = true
            controller.sampleLocalAsset()
            try await Task.sleep(nanoseconds:50_000_000)
            controller.cancelSampling()
            try await Task.sleep(nanoseconds:300_000_000)
            try require(!controller.sampling && controller.sampleProgress == 0,"cancel late isolation")
            controller.sampleLocalAsset()
            for _ in 0..<300 { if !controller.sampling { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.sampleProgress == 1,"24 local sample completed: \(controller.status)")
            controller.parameters = full!.parameters; controller.faithful = true
            controller.savePreset(); controller.savePreset(universal:true)
            controller.parameters = zero; controller.loadPreset()
            try require(controller.parameters == full!.parameters,"associated preset load")
            controller.parameters = zero; controller.loadPreset(universal:true)
            try require(controller.parameters == full!.parameters,"universal preset load")
            controller.manualChange(0,7);try require(controller.parameters.values[0]==7,"manual parameter")
            controller.predicted=full!.parameters;controller.restorePrediction()
            try require(controller.parameters==full!.parameters,"restore prediction")
            controller.exportCube()
            for _ in 0..<100 { if controller.exportedURL != nil { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.exportedURL != nil,"file export")
            controller.importCube(controller.exportedURL!)
            for _ in 0..<100 { if controller.status.hasPrefix("已导入") { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.status.hasPrefix("已导入"),"file import: \(controller.status)")
            try require(controller.parameters == full!.parameters,"CUBE recipe reimport")
            try require(controller.previewCount>0,"bounded preview frames")
            controller.addVideos([movie,movie])
            try require(controller.videoQueue.count==1,"queue dedup")
            controller.generateBatch()
            for _ in 0..<400 { if !controller.batchRunning { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.batchOutputs.count==1,"batch generation: \(controller.batchLog)")
            controller.changePreview(1)
            controller.clearVideoQueue();try require(controller.videoQueue.isEmpty,"queue clear")
            checks.append("actual 24-time local sample completion; preview memory bounds/flip; batch queue dedup/generate/file output/clear; CUBE recipe comments roundtrip")
            controller.clearAllPresets();controller.reset()
            checks.append("production local finite sampling cancellation; associated/universal preset; manual/restore; actual CUBE file export/import; production NativeLUTPanel rendered")
            let data = try JSONSerialization.data(withJSONObject:["inferenceSummary":inferenceSummary,"passed":true,"checks":checks,"boundaries":"Production controller/panel/model use compiled and run; only KSPlayer transport stub and bake counter instrumentation. Neutral non-face fixture attempts real GPU VIDEO inference: inspect inferenceSummary for delegate failure vs no-face. Real face accuracy/physical device FPS NOT RUN. Local synthetic media only."],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:output)
        } catch {
            let data = try! JSONSerialization.data(withJSONObject:["passed":false,"error":String(describing:error),"checks":checks],options:.prettyPrinted)
            try! data.write(to:output)
        }
    }
}
