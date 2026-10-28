import UIKit
import AVFoundation
import CoreImage
import Metal

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
    private let player = AVPlayer(url: URL(string: "http://127.0.0.1:18764/playlist.m3u8")!)
    private var runtime: NativeHLSLUTSurface!
    private var pts: [Double] = []
    private var statuses: [String] = []
    private var pixels: [[UInt8]] = []
    private var pixelPTS: [Double] = []
    private var capture = false
    private var seekCompleted = false
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let layer = AVPlayerLayer(player: player); layer.frame = view.bounds
        layer.videoGravity = .resizeAspect; view.layer.addSublayer(layer)
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        guard let runtime = NativeHLSLUTSurface(player: player, container: overlay) else { finish(["passed": false, "error": "No Metal device"]); return }
        self.runtime = runtime
        runtime.onStatus = { [weak self] value in self?.statuses.append(value) }
        runtime.onPresented = { [weak self] time in self?.pts.append(time.seconds) }
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
                // Sparse samples from the real drawable, not an independently rendered CI image.
                var sample: [UInt8] = []
                for y in stride(from: texture.height / 3, to: texture.height * 2 / 3, by: 11) {
                    for x in stride(from: 0, to: texture.width, by: 13) {
                        let offset = y * row + x * 4
                        sample += [bytes[offset], bytes[offset+1], bytes[offset+2]]
                    }
                }
                Task { @MainActor in self.pixels.append(sample); self.pixelPTS.append(time.seconds) }
            }
        }
        runtime.setFilter { $0 }
        Task { await self.run() }
    }

    private func wait(_ predicate: () -> Bool, seconds: Int = 25) async -> Bool {
        for _ in 0..<(seconds*20) {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    private func run() async {
        player.play()
        let ready = await wait { self.player.currentItem?.status == .readyToPlay }
        let frames = await wait { self.pts.count >= 20 && self.player.currentTime().seconds > 1 }
        let timeBefore = player.currentTime().seconds
        player.pause()
        player.seek(to: CMTime(seconds: 4, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { done in
            Task { @MainActor in self.seekCompleted = done }
        }
        let seekOK = await wait { self.seekCompleted && self.pts.last.map { abs($0 - 4) < 0.2 } == true }
        capture = true; runtime.setFilter { $0 }
        let offOK = await wait { self.pixels.count == 1 }
        try? "off".write(to: documents.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let cube = Self.cube()
        capture = true
        runtime.setFilter { image in
            CIFilter(name: "CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": 33, "inputCubeData": cube, "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!, kCIInputImageKey: image])!.outputImage!
        }
        let onOK = await wait { self.pixels.count == 2 }
        try? "on".write(to: documents.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let visible = !runtime.view.isHidden
        let delta = pixels.count == 2 ? zip(pixels[0], pixels[1]).map { abs(Int($0.0)-Int($0.1)) }.reduce(0,+) : 0
        let samePTS = pixelPTS.count == 2 && abs(pixelPTS[0] - pixelPTS[1]) < 0.001
        let seekFrameCount = pts.count
        player.play()
        let resumes = await wait { self.pts.count > seekFrameCount + 20 && self.player.currentTime().seconds > 6 }
        let toEnd = await wait({ self.player.currentTime().seconds > 11.5 }, seconds: 25)
        player.pause()
        runtime.setFilter(nil)
        let fallback = runtime.view.isHidden
        let unique = Set(pts.map { Int(($0*1000).rounded()) }).count
        finish(["passed": ready && frames && seekOK && offOK && onOK && delta > 1000 && samePTS && visible && resumes && toEnd && fallback,
                "readyToPlay": ready, "timeAdvancedBeforeSeek": timeBefore, "frameCount": pts.count, "uniquePTS": unique,
                "pts": pts, "pausedSeekNewPTS": seekOK, "pausedSeekTarget": 4, "samePTSOnOff": samePTS,
                "pixelPTS": pixelPTS, "gpuDrawablePixelAbsoluteDelta": delta, "offSamples": pixels.first ?? [], "onSamples": pixels.last ?? [],
                "surfaceVisibleAfterGPUCompletion": visible, "resumeAfterSeek": resumes, "toEnd": toEnd,
                "finalCurrentTime": player.currentTime().seconds, "filterOffOriginalFallback": fallback,
                "sameAVPlayer": true, "statuses": statuses, "testOnlyCPUReadback": true])
    }

    private static func cube() -> Data {
        var values: [Float] = []
        for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
            values += [Float(r)/32 * 0.45, Float(g)/32 * 0.8, min(1, Float(b)/32 * 0.7 + 0.2), 1]
        } } }
        return values.withUnsafeBytes { Data($0) }
    }

    private func finish(_ result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: documents.appendingPathComponent("result.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
