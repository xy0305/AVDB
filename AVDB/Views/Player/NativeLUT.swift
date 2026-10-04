// Port of 网页视频实时 LUT @author You @version 6.7.5.
// Source metadata retained in THIRD_PARTY/lut-v6.7.5.txt; no license inferred.
import SwiftUI
import AVFoundation
import CoreImage
import Vision
import KSPlayer

struct LUTParameters: Equatable {
    // temperature, tint, saturation, brightness, contrast, highlights, shadows
    var values: [Double] = [0, 0, 0, 0, 0, 0, 0]
    static let names = ["色温", "色调", "饱和度", "亮度", "对比度", "高光", "阴影"]
}

enum NativeLUT {
    static func lum(_ c: [Double]) -> Double { c[0]*0.2126 + c[1]*0.7152 + c[2]*0.0722 }
    static func transform(_ input: [Double], _ p: LUTParameters) -> [Double] {
        let v = p.values
        var c = input
        var l = lum(c)
        let damp = max(0.3, 1 - max(0, (l-0.7)/0.3)*0.7)
        c = c.map { $0 * (1 + v[3]/50*0.67*damp) }
        l = lum(c)
        let hs = (1 + v[5]/50*0.7*max(0,(l-0.5)/0.5)) * (1 + v[6]/50*0.7*max(0,(0.5-l)/0.5))
        c = c.map { $0*hs }
        var gain = [(1+v[0]/50*0.23)*(1+v[1]/50*0.045), (1+v[0]/50*0.058)*(1-v[1]/50*0.09), (1-v[0]/50*0.23)*(1+v[1]/50*0.045)]
        let normalization = lum(gain)
        if normalization > 0.001 { gain = gain.map { $0/normalization } }
        let protection = 1-min(1,max(0,(lum(c)-0.7)/0.3))*0.95
        c = (0..<3).map { c[$0]*(1+(gain[$0]-1)*protection) }
        l = lum(c)
        c = c.map { l+(1+v[2]/50*1.5)*($0-l) }
        let contrast = 1+v[4]/50*0.57*max(0.5,1-max(0,(lum(c)-0.7)/0.3)*0.5)
        c = c.map { 0.5+contrast*($0-0.5) }
        l = lum(c)
        let white = (c.max()!-c.min()!) < 0.08 && c.min()! > 0.85
        if l > 0.96 && !white { c = c.map { $0*0.96/l } }
        return c.map { min(1,max(0,$0)) }
    }
    static func cube(_ p: LUTParameters) -> Data {
        var floats = [Float]()
        floats.reserveCapacity(33*33*33*4)
        for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
            floats.append(contentsOf: transform([Double(r)/32,Double(g)/32,Double(b)/32],p).map(Float.init))
            floats.append(1)
        } } }
        return floats.withUnsafeBytes { Data($0) }
    }
    // Ported sampleSkinStats: mean ratios, luma, saturation, contrast, HL/SH fractions.
    static func stats(_ pixels: [[Double]]) -> [Double] {
        let n = Double(pixels.count)
        var means = [Double](repeating: 0,count: 3)
        var saturation = 0.0, high = 0.0, low = 0.0
        for c in pixels {
            for i in 0..<3 { means[i] += c[i]/n }
            saturation += (c.max()! > 1e-6 ? (c.max()!-c.min()!)/c.max()! : 0)/n
            if lum(c)>0.7 { high += 1/n }; if lum(c)<0.2 { low += 1/n }
        }
        let l = lum(means)
        let variance = pixels.reduce(0.0) { $0 + pow(lum($1)-l,2)/n }
        return [means[0]/max(1e-6,means[2]),means[0]/max(1e-6,means[1]),l,saturation,sqrt(variance),high,low]
    }
    // Native bounded coordinate search using original templates/target ranges.
    // Not a line-for-line port of browser predictParams' scene-specific guards.
    static func search(_ pixels: [[Double]]) -> LUTParameters {
        let s = stats(pixels)
        let dark = s[2]<0.22 && s[0]<1.6
        var p = LUTParameters(values: dark ? [-18,3,-1,25,-2,-1,20] : [-20,0,0,0,0,-2,2])
        let targets: [[Double]] = dark ? [[1.05,1.32],[1.12,1.28],[0.46,0.66],[0.14,0.25],[0.13,0.23],[0,0.15],[0.14,0.35]] : [[1.2,1.5],[1.15,1.35],[0.4,0.58],[0.12,0.26],[0.1,0.2],[0,0.2],[0,0.4]]
        let ranges = dark ? [(-26,-14),(0,8),(-6,0),(10,45),(-5,0),(-4,1),(5,35)] : [(-50,-16),(-6,6),(-6,4),(-8,50),(-4,3),(-8,2),(-4,8)]
        let base = p.values
        func score(_ candidate: LUTParameters) -> Double {
            let t = stats(pixels.map { transform($0,candidate) })
            var error = 0.0
            let weights = [15.0,5,10,4,2,8,3]
            for i in 0..<7 {
                let d = max(0,max(targets[i][0]-t[i],t[i]-targets[i][1]))
                error += weights[i]*d*d + 0.0001*pow(candidate.values[i]-base[i],2)
            }
            return error
        }
        for _ in 0..<2 { for index in [0,1,3,5,6,2,4] {
            var best = p, bestError = score(p)
            for value in ranges[index].0...ranges[index].1 {
                var trial = p; trial.values[index] = Double(value)
                let e = score(trial)
                if e<bestError { best = trial; bestError = e }
            }
            p = best
        } }
        return p
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
    private var supported = false

    func tick(_ player: KSAVPlayer?) {
        guard let next = player?.player.currentItem else { detach(); return }
        if item !== next {
            detach(); item = next; original = next.videoComposition
            status = "检查视频格式…"
            let token = generation
            Task {
                do {
                    let tracks = try await next.asset.loadTracks(withMediaType: .video)
                    guard let track = tracks.first else { return }
                    let descriptions = try await track.load(.formatDescriptions)
                    let hdr = descriptions.contains { d in
                        guard let extensions = CMFormatDescriptionGetExtensions(d) else { return false }
                        let ext = extensions as NSDictionary
                        let transfer = ext[kCMFormatDescriptionExtension_TransferFunction] as? String
                        return transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    }
                    let playable = try await next.asset.load(.isComposable)
                    guard generation == token, item === next else { return }
                    let hls = (next.asset as? AVURLAsset)?.url.pathExtension.lowercased() == "m3u8"
                    guard playable && !hdr && !hls else {
                        status = hdr ? "HDR 不支持 LUT" : "此视频不支持原生 composition LUT（HLS/非可合成流）"
                        enabled = false; return
                    }
                    supported = true
                    let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    next.add(out); output = out
                    status = "SDR 就绪，点击开启 LUT"
                } catch { if generation == token { status = "格式检查失败：\(error.localizedDescription)" } }
            }
        }
        if supported && enabled && requested && !busy { analyze() }
    }
    func detach() {
        generation += 1
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
        let cube = NativeLUT.cube(parameters)
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
        busy = true; requested = false; status = "Vision 自动分析…"
        let token = generation
        let ciImage = CIImage(cvPixelBuffer:buffer)
        let scale = min(1,640/max(ciImage.extent.width,ciImage.extent.height))
        guard let image = context.createCGImage(ciImage.transformed(by:CGAffineTransform(scaleX:scale,y:scale)),from:CGRect(x:0,y:0,width:ciImage.extent.width*scale,height:ciImage.extent.height*scale)) else { busy = false; requested = true; return }
        Task {
            let result = await Task.detached(priority:.userInitiated) { () -> (LUTParameters, String)? in
                let face = VNDetectFaceRectanglesRequest()
                try? VNImageRequestHandler(cgImage:image).perform([face])
                let box = face.results?.max(by: { $0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height })?.boundingBox
                let region = box ?? CGRect(x:0.25,y:0.25,width:0.5,height:0.5)
                let w = image.width, h = image.height
                var bytes = [UInt8](repeating:0,count:w*h*4)
                guard let ctx = CGContext(data:&bytes,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
                var skin = [[Double]](), fallback = [[Double]]()
                for y in stride(from:0,to:h,by:3) { for x in stride(from:0,to:w,by:3) {
                    guard region.contains(CGPoint(x:Double(x)/Double(w),y:1-Double(y)/Double(h))) else { continue }
                    let i = (y*w+x)*4
                    let r = Double(bytes[i]), g = Double(bytes[i+1]), b = Double(bytes[i+2])
                    let pixel = [r/255,g/255,b/255]
                    fallback.append(pixel)
                    let cb = 128-0.168736*r-0.331264*g+0.5*b
                    let cr = 128+0.5*r-0.418688*g-0.081312*b
                    if (77...127).contains(cb) && (130...180).contains(cr) && NativeLUT.lum(pixel)<0.9 { skin.append(pixel) }
                } }
                let selected = skin.count >= 150 ? skin : fallback
                guard selected.count >= 30 else { return nil }
                let step = max(1,selected.count/400)
                let coarse = stride(from:0,to:selected.count,by:step).prefix(400).map { selected[$0] }
                return (NativeLUT.search(coarse),box == nil ? "中央区域" : "Vision 人脸区域")
            }.value
            guard generation == token else { return }
            busy = false
            guard let result else { status = "采样不足，请重新分析"; return }
            parameters = result.0; apply(); status = "33³ LUT · \(result.1) · SDR"
        }
    }
}

struct NativeLUTPanel: View {
    @ObservedObject var model: NativeLUTController
    var body: some View {
        Form {
            Text(model.status).font(.footnote)
            Button(model.enabled ? "关闭 LUT" : "开启 LUT") { model.toggle() }
            Button("重新分析原始帧") { model.reanalyze() }
            Button("重置 / 原始画面") { model.reset() }
            ForEach(0..<7,id:\.self) { i in
                VStack(alignment:.leading) {
                    Text("\(LUTParameters.names[i]) \(Int(model.parameters.values[i]))")
                    Slider(value:Binding(get:{ model.parameters.values[i] },set:{ model.parameters.values[i] = $0; model.apply() }),in:-50...50,step:1)
                }
            }
        }.presentationDetents([.medium,.large])
    }
}
