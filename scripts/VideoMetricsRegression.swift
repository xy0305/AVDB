import Foundation

@main struct MetricsRegression {
    @MainActor static func main() {
        func size(_ w: Double, _ h: Double, _ evidence: PlaybackVideoMetrics.Evidence = .presentation) -> PlaybackVideoMetrics? {
            PlaybackVideoMetrics(width: w, height: h, evidence: evidence)
        }
        for (w,h,grade) in [(3840.0,2160.0,"4K"),(4096,2160,"4K"),(1920,1080,"1080p"),(1080,1920,"1080p"),(2160,3840,"4K"),(1280,720,"720p"),(1024,576,"576p"),(2048,858,"858p")] {
            precondition(size(w,h)?.grade == grade)
            precondition(size(w,h)?.width == Int(w) && size(w,h)?.height == Int(h))
        }
        for (w,h) in [(0.0,1080.0),(-1,1080),(Double.nan,1080),(1920,Double.infinity),(Double.infinity,0),(0,0)] {
            precondition(size(w,h) == nil)
        }
        let original = Pan115Client.PlayStream(name: "原文件 / 原画", url: "https://example.test/original", isOriginal: true)
        let refreshed = Pan115Client.PlayStream(name: original.name, url: "https://example.test/new-signed", isOriginal: true)
        let hls = Pan115Client.PlayStream(name: "1080P", url: "https://example.test/hls", isOriginal: false)
        let vm = ShippingHarness()
        vm.activate(original)
        precondition(vm.isCurrent(original) && vm.isCurrent(refreshed) && !vm.isCurrent(hls))
        precondition(vm.qualityLabel == "原画·检测中")
        let first = vm.metricsGeneration
        vm.receiveMetrics(size(3840,2160), settled: true, url: URL(string: original.url)!, generation: first)
        precondition(vm.qualityLabel == "原画·4K" && vm.resolutionDetail.contains("3840×2160"))
        vm.activate(hls) // identical shipping activate used by failed() fallback
        precondition(vm.isCurrent(hls) && !vm.isCurrent(original))
        precondition(vm.qualityLabel == "HLS·检测中" && !vm.resolutionDetail.contains("3840"))
        let second = vm.metricsGeneration
        vm.receiveMetrics(size(3840,2160), settled: true, url: URL(string: original.url)!, generation: second)
        precondition(vm.qualityLabel == "HLS·检测中") // wrong URL, current generation
        vm.receiveMetrics(size(3840,2160), settled: true, url: URL(string: hls.url)!, generation: first)
        precondition(vm.qualityLabel == "HLS·检测中") // correct URL, stale generation
        vm.receiveMetrics(size(1920,1080), settled: true, url: URL(string: hls.url)!, generation: second)
        precondition(vm.qualityLabel == "HLS·1080p")
        vm.receiveMetrics(size(1280,720), settled: true, url: URL(string: hls.url)!, generation: second)
        precondition(vm.qualityLabel == "HLS·720p") // adaptive update
        vm.activate(hls) // same URL restart must still clear and reject old completion
        vm.receiveMetrics(size(1920,1080), settled: true, url: URL(string: hls.url)!, generation: second)
        precondition(vm.qualityLabel == "HLS·检测中")
        vm.receiveMetrics(nil, settled: true, url: URL(string: hls.url)!, generation: vm.metricsGeneration)
        precondition(vm.qualityLabel == "HLS·未知")
        vm.receiveMetrics(size(1920,1080,.track), settled: true, url: URL(string: hls.url)!, generation: vm.metricsGeneration)
        precondition(vm.qualityLabel == "HLS·1080p(轨道)" && vm.resolutionDetail.contains("轨道分辨率"))
        vm.clearMetrics()
        precondition(!vm.resolutionDetail.contains("1920"))
        print("PASS production metrics policy and extracted shipping VM wiring: dimensions/orientation/invalid values, signed-URL identity, stale URL+generation, same URL restart, source reset, fallback identity, adaptive update, unknown and track evidence")
    }
}
