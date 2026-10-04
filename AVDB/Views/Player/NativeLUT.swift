// Port of 网页视频实时 LUT @author You @version 6.7.5.
// Source metadata retained in THIRD_PARTY/lut-v6.7.5.txt; no license inferred.
import SwiftUI
import AVFoundation
import CoreImage
import Vision
import JavaScriptCore
import KSPlayer

struct LUTParameters: Equatable {
    // temperature, tint, saturation, brightness, contrast, highlights, shadows
    var values: [Double] = [0, 0, 0, 0, 0, 0, 0]
    static let names = ["色温", "色调", "饱和度", "亮度", "对比度", "高光", "阴影"]
}

// Each invocation owns an isolated JavaScriptCore VM; no DOM, network or WebGL.
// Analysis is called only from the detached worker. Cube generation uses its own VM.
enum NativeLUT {
    private static func engine() -> JSContext? {
        guard let url = Bundle.main.url(forResource: "OriginalLUT", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(source)
        guard context.exception == nil else { return nil }
        return context
    }
    static func analyze(bytes: [UInt8], width: Int, height: Int, box: [String: Int]?) -> (LUTParameters, String)? {
        guard let context = engine(),
              let result = context.objectForKeyedSubscript("OriginalLUT")?.objectForKeyedSubscript("analyzeFrame")?.call(withArguments: [bytes, width, height, box as Any? ?? NSNull()]),
              context.exception == nil, !result.isNull, !result.isUndefined,
              let dict = result.toDictionary(), let params = dict["params"] as? [String: Any] else { return nil }
        let keys = ["temp", "tint", "sat", "bright", "contrast", "highlight", "shadow"]
        let values = keys.compactMap { (params[$0] as? NSNumber)?.doubleValue }
        guard values.count == 7, values.allSatisfy({ $0.isFinite }) else { return nil }
        return (LUTParameters(values: values), dict["stage"] as? String ?? "标准")
    }
    static func cube(_ p: LUTParameters) -> Data? {
        guard let context = engine(),
              let result = context.objectForKeyedSubscript("OriginalLUT")?.objectForKeyedSubscript("cubeRGBA")?.call(withArguments: [p.values]),
              context.exception == nil, let numbers = result.toArray() as? [NSNumber], numbers.count == 33*33*33*4 else { return nil }
        let floats = numbers.map { $0.floatValue }
        return floats.withUnsafeBytes { Data($0) }
    }
}

@MainActor
final class NativeLUTController: ObservableObject {
    @Published var enabled = false
    @Published var status = "LUT 未启用（仅 SDR 文件视频）"
    @Published var parameters = LUTParameters()
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var original: AVVideoComposition?
    private var requested = true
    private var busy = false
    private var generation = 0
    private var composition: AVVideoComposition?
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private(set) var supported = false
    private var formatTask: Task<Void, Never>?
    private var formatTimeout: Task<Void, Never>?

    private func finishFormatCheck(_ token: Int, _ next: AVPlayerItem, message: String, ready: Bool = false) {
        guard generation == token, item === next else { return }
        formatTimeout?.cancel(); formatTimeout = nil
        formatTask?.cancel(); formatTask = nil
        supported = ready; enabled = false; status = message
        if ready {
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            next.add(out); output = out
        }
    }

    func tick(_ player: KSAVPlayer?) {
        guard let next = player?.player.currentItem else { detach(); return }
        if item !== next {
            detach(); item = next; original = next.videoComposition
            status = "检查视频格式…"
            let token = generation
            // Reject known HLS before any remote AVAsset property loading.
            if (next.asset as? AVURLAsset)?.url.pathExtension.lowercased() == "m3u8" {
                finishFormatCheck(token, next, message: "HLS 不支持原生 composition LUT")
                return
            }
            formatTimeout = Task { [weak self, weak next] in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                guard let self, let next, self.generation == token, self.item === next else { return }
                // Invalidate first: even a property loader ignoring cancellation cannot publish late.
                self.finishFormatCheck(token, next, message: "格式检查超时，LUT 已禁用；视频可继续播放")
                self.generation += 1
            }
            formatTask = Task { [weak self, weak next] in
                guard let self, let next else { return }
                do {
                    let tracks = try await next.asset.loadTracks(withMediaType: .video)
                    try Task.checkCancellation()
                    guard let track = tracks.first else {
                        finishFormatCheck(token, next, message: "未发现视频轨道，LUT 已禁用")
                        return
                    }
                    let descriptions = try await track.load(.formatDescriptions)
                    try Task.checkCancellation()
                    guard !descriptions.isEmpty else {
                        finishFormatCheck(token, next, message: "视频格式信息为空，LUT 已禁用")
                        return
                    }
                    let hdr = descriptions.contains { d in
                        guard let extensions = CMFormatDescriptionGetExtensions(d) else { return false }
                        let ext = extensions as NSDictionary
                        let transfer = ext[kCMFormatDescriptionExtension_TransferFunction] as? String
                        return transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    }
                    let playable = try await next.asset.load(.isComposable)
                    guard generation == token, item === next else { return }
                    try Task.checkCancellation()
                    guard generation == token, item === next else { return }
                    guard playable && !hdr else {
                        finishFormatCheck(token, next, message: hdr ? "HDR 不支持 LUT" : "此视频不支持原生 composition LUT（HLS/非可合成流）")
                        return
                    }
                    finishFormatCheck(token, next, message: "SDR 就绪，点击开启 LUT", ready: true)
                } catch {
                    guard !Task.isCancelled else { return }
                    finishFormatCheck(token, next, message: "格式检查失败，LUT 已禁用：\(error.localizedDescription)")
                }
            }
        }
        if supported && enabled && requested && !busy { analyze() }
    }
    func detach() {
        generation += 1
        formatTask?.cancel(); formatTask = nil
        formatTimeout?.cancel(); formatTimeout = nil
        enabled = false
        status = "等待播放器视频轨道；LUT 未启用"
        if let item { item.videoComposition = original; if let output { item.remove(output) } }
        item = nil; output = nil; original = nil; composition = nil
        supported = false; busy = false; requested = true
    }
    func toggle() {
        guard supported else { return }
        enabled.toggle()
        if enabled { if let composition { item?.videoComposition = composition } else { requested = true } }
        else { item?.videoComposition = original }
    }
    func reanalyze() {
        guard supported else { return }
        item?.videoComposition = original
        requested = true; status = "等待原始解码帧…"
    }
    func reset() {
        enabled = false; parameters = LUTParameters(); composition = nil
        item?.videoComposition = original; requested = true; status = "已重置"
    }
    func apply() {
        guard supported, let item else { return }
        guard let cube = NativeLUT.cube(parameters) else { status = "原版 LUT 引擎加载失败，未应用调色"; return }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ci = context
        let comp = AVVideoComposition(asset: item.asset, applyingCIFiltersWithHandler: { request in
            guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: ["inputCubeDimension":33,"inputCubeData":cube,"inputColorSpace":cs,kCIInputImageKey:request.sourceImage]) else {
                request.finish(with: NSError(domain:"AVDB.LUT",code:1)); return
            }
            guard let result = filter.outputImage else {
                request.finish(with: NSError(domain:"AVDB.LUT",code:2)); return
            }
            request.finish(with: result.cropped(to:request.sourceImage.extent),context:ci)
        })
        composition = comp
        if enabled { item.videoComposition = comp }
    }
    private func analyze() {
        guard let item, let output, item.videoComposition == nil else { return }
        let time = item.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else { return }
        // Conservative transfer-function check on the actual decoded frame too.
        if let transfer = CVBufferCopyAttachment(buffer,kCVImageBufferTransferFunctionKey,nil) as? String,
           transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
            enabled = false; supported = false; status = "HDR 解码帧已禁用 LUT"; return
        }
        busy = true; requested = false; status = "获取 Vision ROI → 原版动态 Cr / 分阶段搜索…"
        let token = generation
        let ciImage = CIImage(cvPixelBuffer:buffer)
        let scale = 640/max(ciImage.extent.width,ciImage.extent.height)
        guard let image = context.createCGImage(ciImage.transformed(by:CGAffineTransform(scaleX:scale,y:scale)),from:CGRect(x:0,y:0,width:ciImage.extent.width*scale,height:ciImage.extent.height*scale)) else { busy = false; requested = true; return }
        Task {
            let result = await Task.detached(priority:.userInitiated) { () -> (LUTParameters, String)? in
                let face = VNDetectFaceRectanglesRequest()
                try? VNImageRequestHandler(cgImage:image).perform([face])
                let box = face.results?.max(by: { $0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height })?.boundingBox
                let w = image.width, h = image.height
                var bytes = [UInt8](repeating: 0, count: w*h*4)
                guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                // Vision supplies a rectangle, not MediaPipe landmark extrema. Never claim ROI parity.
                let roi: [String: Int]? = box.map { rect in
                    ["x1": max(0, Int(floor(rect.minX * Double(w)))),
                     "y1": max(0, Int(floor((1-rect.maxY) * Double(h)))),
                     "x2": min(w, Int(ceil(rect.maxX * Double(w)))),
                     "y2": min(h, Int(ceil((1-rect.minY) * Double(h))))]
                }
                guard let analysis = NativeLUT.analyze(bytes: bytes, width: w, height: h, box: roi) else { return nil }
                return (analysis.0, "原版6.7.5 · \(analysis.1) · \(box == nil ? "中央50%" : "Vision ROI（非MediaPipe）")")
            }.value
            guard generation == token else { return }
            busy = false
            guard let result else { status = "原版肤色采样不足（<150）或引擎失败；保留旧 LUT"; return }
            parameters = result.0; apply(); status = "33³ LUT · \(result.1) · SDR"
        }
    }
}

struct NativeLUTPanel: View {
    @ObservedObject var model: NativeLUTController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
        Form {
            Text(model.status).font(.footnote)
            Group {
            Button(model.enabled ? "关闭 LUT" : "开启 LUT") { model.toggle() }
            Button("重新分析原始帧") { model.reanalyze() }
            Button("重置 / 原始画面") { model.reset() }
            ForEach(0..<7,id:\.self) { i in
                VStack(alignment:.leading) {
                    Text("\(LUTParameters.names[i]) \(Int(model.parameters.values[i]))")
                    Slider(value:Binding(get:{ model.parameters.values[i] },set:{ model.parameters.values[i] = $0; model.apply() }),in:-50...50,step:1)
                }
            }
            }.disabled(!model.supported)
            Section {
                Text("原文件的容器、编码及 HDR 支持取决于设备；LUT 仅支持可分析的 SDR。开启或分析后，点右上角返回播放；分析无需停留在此面板等待。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("LUT 调色")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Label("返回播放", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("完成 LUT 设置，返回播放")
                .accessibilityHint("关闭面板，保留调色设置与播放进度")
            }
        }
        }.presentationDetents([.medium,.large])
    }
}
