import UIKit
import AVFoundation
import CoreImage
import Metal
import KSPlayer

@main
final class App: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = Host(); window.makeKeyAndVisible(); self.window = window
        return true
    }
}

@MainActor
final class Host: UIViewController {
    private var backend: KSAVPlayer!
    private let model = NativeLUTController()
    private var player: AVQueuePlayer { backend.player }
    private var runtime: NativeHLSLUTSurface { model.testSurface! }
    private var pts: [Double] = []
    private var pixels: [[UInt8]] = []
    private var pixelPTS: [Double] = []
    private var capture = false
    private var geometry: [String: Double] = [:]
    private var seekCompleted = false
    private var checks: [String: Bool] = [:]
    private var measures: [String: Any] = [:]
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let options = KSOptions()
        backend = KSAVPlayer(url: URL(string: "http://127.0.0.1:18764/playlist.m3u8")!, options: options)
        backend.prepareToPlay()
        backend.playerLayer.frame = view.bounds
        backend.playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(backend.playerLayer)
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false; view.addSubview(overlay)
        model.setContainer(overlay); model.tick(backend)
        guard model.testSurface != nil else { finish(["passed": false, "error": "No controller surface"]); return }
        runtime.testGeometry = { [weak self] in self?.geometry = $0 }
        let productionPresented = runtime.onPresented
        runtime.onPresented = { [weak self] time in productionPresented?(time); self?.pts.append(time.seconds) }
        runtime.testEncode = { [weak self] texture, command, time in
            guard let self, self.capture else { return }
            self.capture = false
            let row = (texture.width * 4 + 255) & ~255
            guard let buffer = texture.device.makeBuffer(length: row * texture.height, options: .storageModeShared), let blit = command.makeBlitCommandEncoder() else { return }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: row, destinationBytesPerImage: row * texture.height)
            blit.endEncoding()
            command.addCompletedHandler { completed in
                guard completed.status == .completed else { return }
                let bytes = buffer.contents().assumingMemoryBound(to: UInt8.self)
                var sample: [UInt8] = []
                // Cover full width for split and black-border assertions.
                for y in stride(from: texture.height / 3, to: texture.height * 2 / 3, by: 11) {
                    for x in stride(from: 0, to: texture.width, by: 13) {
                        let offset = y * row + x * 4
                        sample += [bytes[offset], bytes[offset+1], bytes[offset+2]]
                    }
                }
                Task { @MainActor in self.pixels.append(sample); self.pixelPTS.append(time.seconds) }
            }
        }
        checks["sameKSAVQueuePlayer"] = backend.playerLayer.player === player
        checks["noninteractiveOverlay"] = !overlay.isUserInteractionEnabled && !runtime.view.isUserInteractionEnabled
        Task { await self.run(overlay: overlay) }
    }
    private func wait(_ predicate: () -> Bool, seconds: Int = 25) async -> Bool {
        for _ in 0..<(seconds*20) {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }
    private func render(parameters: [Double], strength: Double, split: Double?) async -> Bool {
        let count = pixels.count
        model.enabled = true; model.parameters = LUTParameters(values: parameters)
        model.strength = strength; model.comparison = split != nil
        model.divider = split ?? 0.5; model.updateComparison()
        // Avoid collecting the previous filter's dirty frame before its replacement.
        let revision = model.testAppliedBuild
        model.apply()
        guard await wait({ self.model.testAppliedBuild > revision }) else { return false }
        capture = true; model.updateComparison()
        return await wait { self.pixels.count > count }
    }
    private func delta(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a,b).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) } }
    private func run(overlay: UIView) async {
        backend.play()
        checks["readyToPlay"] = await wait { self.player.currentItem?.status == .readyToPlay && self.model.supported }
        checks["sourceCheckNotPresentation"] = pts.isEmpty && runtime.view.isHidden
        checks["analysisNilRequestRetained"] = model.testAnalysisRequested
        // Actual production controller + 6.7.8 JavaScriptCore cube, not a demo cube.
        let adjusted: [Double] = [22, -12, 30, 18, 16, -15, 20]
        model.enabled = true; model.parameters = LUTParameters(values: adjusted); model.comparison = true; model.divider = 0
        model.updateComparison(); model.apply()
        checks["decodedAndPresented"] = await wait { self.pts.count >= 20 && self.player.currentTime().seconds > 1 }
        backend.pause()
        player.seek(to: CMTime(seconds: 4, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { done in Task { @MainActor in self.seekCompleted = done } }
        checks["pausedSeekNewPTS"] = await wait { self.seekCompleted && self.pts.last.map { abs($0-4) < 0.2 } == true }
        checks["strengthZeroCaptured"] = await render(parameters: adjusted, strength: 0, split: 0)
        await snapshotStage("strength-zero")
        checks["strengthOneCaptured"] = await render(parameters: adjusted, strength: 1, split: 0)
        await snapshotStage("actual-678-lut")
        checks["splitCaptured"] = await render(parameters: adjusted, strength: 1, split: 0.5)
        await snapshotStage("same-frame-split")
        checks["neutralParametersCaptured"] = await render(parameters: [0,0,0,0,0,0,0], strength: 1, split: 0)
        if pixels.count == 4 {
            let d = delta(pixels[0], pixels[1]); let neutral = delta(pixels[0], pixels[3])
            checks["userParametersChangeActualGPUPixels"] = d > 1000
            checks["strengthZeroMatchesNeutralOriginal"] = neutral < 2500
            checks["sameFrameSplit"] = verifySplit(original: pixels[0], filtered: pixels[1], split: pixels[2])
            checks["blackBordersUnaffected"] = pixels.allSatisfy { $0.prefix(30).allSatisfy { $0 == 0 } }
            measures["gpuDrawableParameterDelta"] = d; measures["strengthZeroNeutralDelta"] = neutral
        }
        checks["samePTSAllParameterCaptures"] = pixelPTS.count == 4 && pixelPTS.allSatisfy { abs($0-4) < 0.1 }
        checks["productionUIStatusAfterGPU"] = model.status.contains("在线 SDR LUT：Metal")
        checks["hlsNeverVideoComposition"] = player.currentItem?.videoComposition == nil
        let originalOutput = runtime.output
        let first = runtime.copyDecodedFrameForAnalysis()
        let throttled = runtime.copyDecodedFrameForAnalysis()
        checks["sharedAnalysisOutputAndThrottle"] = first != nil && throttled == nil && runtime.output === originalOutput
        model.setLayoutCompatible(false)
        checks["fillModeOriginalBypass"] = runtime.view.isHidden
        model.setLayoutCompatible(true)
        // Explicit PiP owner bypass; real external PiP remains a device-only test.
        model.setNativeBypass("PiP：原画")
        checks["pipOwnerBypass"] = runtime.view.isHidden
        model.setNativeBypass(nil)
        // This focused controller host has no KSPlayerLayer delegate/coordinator.
        // Update the actual backend state, then explicitly resume its SAME queue
        // after the paused raw AV seek (the full App uses its normal coordinator).
        let before = pts.count; backend.play(); player.play()
        measures["hostNativeQueueResumeWithoutKSLayerDelegate"] = true
        checks["resumeAfterSeek"] = await wait { self.pts.count > before + 20 && self.player.currentTime().seconds > 6 }
        checks["toEnd"] = await wait { self.player.currentTime().seconds > 11.5 }
        backend.pause()
        model.enabled = false; model.sharpen = false; model.deband = false; model.apply()
        checks["disableOriginalFallback"] = runtime.view.isHidden && player.currentItem?.videoComposition == nil
        model.enabled = true; model.apply(); model.reset()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        checks["resetRejectsLateCube"] = runtime.view.isHidden && !model.enabled
        let old = runtime
        model.enabled = true; model.apply(); model.removeContainer(overlay)
        try? await Task.sleep(nanoseconds: 500_000_000)
        checks["destroyNoLatePublication"] = old.view.superview == nil && old.output == nil && model.testSurface == nil
        measures["presentations"] = pts.count; measures["uniquePTS"] = Set(pts.map { Int(($0*1000).rounded()) }).count
        measures["pixelPTS"] = pixelPTS; measures["geometry"] = geometry; measures["finalTime"] = player.currentTime().seconds
        finish(["passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "checks": checks, "measurements": measures, "productionSources": ["NativeLUT.swift", "NativeHLSLUTSurface.swift", "OriginalLUT.js", "KSPlayer.KSAVPlayer"], "faceInferenceVerified": false, "gpuReadbackDebugHostOnly": true])
    }
    private func verifySplit(original: [UInt8], filtered: [UInt8], split: [UInt8]) -> Bool {
        let width = Int(geometry["drawableWidth"] ?? 0)
        let height = Int(geometry["drawableHeight"] ?? 0)
        guard width > 0, height > 0 else { return false }
        let columns = (width + 12) / 13
        let fitX = geometry["fitX"] ?? 0, fitY = geometry["fitY"] ?? 0
        let fitWidth = geometry["fitWidth"] ?? 0, fitHeight = geometry["fitHeight"] ?? 0
        let rim = 2 * fitWidth / max(1, geometry["sourceWidth"] ?? 1)
        var leftError = 0, rightError = 0, count = 0
        var rawLeftError = 0, rawRightError = 0
        for i in stride(from: 0, to: min(original.count, min(filtered.count, split.count)), by: 3) {
            let x = ((i/3) % columns) * 13
            let y = height / 3 + ((i/3) / columns) * 11
            if abs(x - width/2) < 20 { continue }
            let interior = Double(x) >= fitX + rim && Double(x) <= fitX + fitWidth - rim && Double(y) >= fitY + rim && Double(y) <= fitY + fitHeight - rim
            for c in 0..<3 {
                let error = abs(Int((x < width/2 ? original : filtered)[i+c])-Int(split[i+c]))
                if x < width/2 { rawLeftError += error } else { rawRightError += error }
                if interior {
                    if x < width/2 { leftError += error } else { rightError += error }
                    count += 1
                }
            }
        }
        // CI's independently cropped branches have different subpixel alpha at
        // the outer image rim. Compare real content, excluding TWO source pixels;
        // keep both raw-rim errors and the unchanged 1200 error threshold visible.
        measures["splitRawLeftIncludingImageRimError"] = rawLeftError
        measures["splitRawRightIncludingImageRimError"] = rawRightError
        measures["splitExcludedOuterSourcePixels"] = 2
        measures["splitInteriorComparedChannels"] = count
        measures["splitLeftOriginalError"] = leftError; measures["splitRightFilteredError"] = rightError
        return count > 1000 && leftError < 1200 && rightError < 1200
    }
    private func snapshotStage(_ name: String) async {
        try? name.write(to: documents.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
        _ = await wait({ (try? String(contentsOf: self.documents.appendingPathComponent("ack.txt"), encoding: .utf8)) == name }, seconds: 15)
    }
    private func finish(_ result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: documents.appendingPathComponent("result.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
