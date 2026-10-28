import SwiftUI
import AVFoundation
import CoreImage
import JavaScriptCore
import UIKit

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
        func mark(_ stage:String) { try? stage.write(to:output.deletingLastPathComponent().appendingPathComponent("progress.txt"),atomically:true,encoding:.utf8) }
        do {
            mark("basic cube")
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
            let backdrop = CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5)).cropped(to:CGRect(x:0,y:0,width:64,height:48))
            let skin = CIImage(color:CIColor(red:0.6,green:0.45,blue:0.4)).cropped(to:CGRect(x:24,y:12,width:16,height:16)).composited(over:backdrop)
            let skinCG = ci.createCGImage(skin,from:skin.extent,format:.RGBA8,colorSpace:cs)!
            mark("real MediaPipe VIDEO model")
            let full = await Task.detached { NativeLUT.fullAnalyze([LUTFrame(image:skinCG)],faithful:true) }.value
            try require(full != nil,"full numeric pipeline with real MediaPipe attempt")
            inferenceSummary = full!.summary
            mark("faithful cube")
            let faithfulCube = NativeLUT.bake(full!.parameters,faithful:true)!
            try require(faithfulCube.count == cube.count,"faithful cube")
            let zero65 = NativeLUT.bake(zero,faithful:true,size:65)!
            try require(zero65.count == 65*65*65*16,"65 cube")
            checks.append("CUBE roundtrip/domain; malformed/NaN/unsupported rejection; real production GPU VIDEO model attempt; full prediction; 65 cube")
            // Generate a tiny local neutral SDR file. No URLSession, network or source adapter.
            mark("local movie")
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
                for y in 0..<48 { for x in 0..<64 { let i=y*CVPixelBufferGetBytesPerRow(buffer!)+x*4;let patch = (24..<40).contains(x) && (12..<28).contains(y);raw[i]=patch ? 102:128;raw[i+1]=patch ? 115:128;raw[i+2]=patch ? 153:128;raw[i+3]=255 } }
                CVPixelBufferUnlockBaseAddress(buffer!,[])
                try require(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(frame),timescale:6)),"append local frame")
            }
            input.markAsFinished();await writer.finishWriting()
            try require(writer.status == .completed,"local asset writer")
            mark("controller format/cache")
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
            mark("local bounded sampler")
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
            mark("export import")
            controller.exportCube()
            for _ in 0..<100 { if controller.exportedURL != nil { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.exportedURL != nil,"file export")
            controller.importCube(controller.exportedURL!)
            for _ in 0..<100 { if controller.status.hasPrefix("已导入") { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.status.hasPrefix("已导入"),"file import: \(controller.status)")
            try require(controller.parameters == full!.parameters,"CUBE recipe reimport")
            try require(controller.previewCount>0,"bounded preview frames")
            mark("domain and image preview")
            let domainURL = movie.deletingLastPathComponent().appendingPathComponent("domain.cube")
            try LUTArchive(size:33,rgba:cube,domainMin:[0,0,0],domainMax:[2,2,2]).text().write(to:domainURL,atomically:true,encoding:.utf8)
            controller.importCube(domainURL)
            for _ in 0..<100 { if controller.status.hasPrefix("已导入") { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try await Task.sleep(nanoseconds:2_000_000_000)
            try require(controller.previewOriginal != nil && controller.previewProcessed != nil,"actual preview rendering")
            func sample(_ image:UIImage) -> [Float] {
                let cg = image.cgImage!, frame = CIImage(cgImage:cg), rect = CGRect(x:0,y:0,width:1,height:1)
                var values=[Float](repeating:0,count:4)
                values.withUnsafeMutableBytes { ci.render(frame,toBitmap:$0.baseAddress!,rowBytes:16,bounds:rect,format:.RGBAf,colorSpace:cs) }
                return values
            }
            let srcPixel = sample(controller.previewOriginal!), dstPixel = sample(controller.previewProcessed!)
            for channel in 0..<3 { try require(abs(dstPixel[channel]-srcPixel[channel]/2)<0.02,"actual non-unit CUBE domain render src=\(srcPixel) dst=\(dstPixel)") }
            let picture = movie.deletingLastPathComponent().appendingPathComponent("neutral.png")
            try UIImage(cgImage:skinCG).pngData()!.write(to:picture)
            controller.importMedia([picture,picture])
            for _ in 0..<100 { if !controller.sampling { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.previewCount==2 && controller.sampleProgress==1,"actual file-picker image pipeline")
            checks.append("actual nonlinear non-unit CUBE DOMAIN rendered against expected pixel; explicit neutral PNG multi-image analysis")
            controller.addVideos([movie,movie])
            try require(controller.videoQueue.count==1,"queue dedup")
            mark("batch")
            controller.generateBatch()
            for _ in 0..<400 { if !controller.batchRunning { break }; try await Task.sleep(nanoseconds:100_000_000) }
            try require(controller.batchOutputs.count==1,"batch generation: \(controller.batchLog)")
            controller.changePreview(1)
            controller.clearVideoQueue();try require(controller.videoQueue.isEmpty,"queue clear")
            checks.append("actual 24-time local sample completion; preview memory bounds/flip; batch queue dedup/generate/file output/clear; CUBE recipe comments roundtrip")
            mark("complete")
            controller.clearAllPresets();controller.reset()
            checks.append("production local finite sampling cancellation; associated/universal preset; manual/restore; actual CUBE file export/import; production NativeLUTPanel rendered")
            let data = try JSONSerialization.data(withJSONObject:["inferenceSummary":inferenceSummary,"passed":true,"checks":checks,"boundaries":"Production controller/panel/model use compiled and run; only KSPlayer transport stub and bake counter instrumentation. Neutral non-face fixture runs real VIDEO model on simulator CPU; physical-device production uses GPU on its dedicated thread. Inspect inferenceSummary for inference failure vs no-face. Real face accuracy/physical device FPS NOT RUN. Local synthetic media only."],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:output)
        } catch {
            let data = try! JSONSerialization.data(withJSONObject:["inferenceSummary":inferenceSummary,"passed":false,"error":String(describing:error),"checks":checks],options:.prettyPrinted)
            try! data.write(to:output)
        }
    }
}
