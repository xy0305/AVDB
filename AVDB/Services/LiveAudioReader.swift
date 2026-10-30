// Build 287 — look-ahead audio reader for live subtitles.
//
// A second, audio-only FFmpeg demux/decode context that runs *ahead of the playhead* on its own thread.
// It works for every source the player can open (115 / online HLS / AVPlayer + Metal LUT path / local files),
// because it never taps the player's render path: it reads the same URL with the same HTTP headers,
// discards every non-audio stream and resamples to 16 kHz mono Float32 for Whisper.
// MTAudioProcessingTap does not see HLS, and AVAssetReader cannot open HLS, so this is the single capture path.
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswresample

final class LiveAudioReader: @unchecked Sendable {
    struct Source: Equatable {
        var url: URL
        var headers: [String: String] = [:]
    }

    /// Called on the reader thread with (samples, media start time in s, generation).
    var onPCM: (([Float], Double, Int) -> Void)?
    /// Called once the stream is exhausted (generation).
    var onEnd: ((Int) -> Void)?
    var onError: ((String) -> Void)?
    /// Pacing: return false to make the reader wait (it is far enough ahead of the playhead).
    var shouldRun: (() -> Bool)?
    /// Return a media time to jump to when the region ahead is already covered by cached subtitles.
    var skipTarget: ((Double) -> Double?)?

    private let cond = NSCondition()
    private var thread: Thread?
    private var source: Source?
    private var pendingSeek: (time: Double, generation: Int)?
    private var stopped = true
    private var token = 0                 // each start() gets a fresh worker; stale threads exit on their own
    fileprivate var interrupted = false   // read by the FFmpeg interrupt callback
    private(set) var duration: Double = 0

    static let chunkSamples = 4000        // 0.25 s @ 16 kHz

    func start(_ source: Source, at time: Double, generation: Int) {
        stop()
        cond.lock()
        self.source = source
        pendingSeek = (max(0, time), generation)
        stopped = false
        interrupted = false
        token += 1
        let tok = token
        let t = Thread { [weak self] in self?.run(tok) }
        t.name = "live287.audio"
        t.qualityOfService = .utility
        thread = t
        cond.unlock()
        t.start()
    }

    func seek(to time: Double, generation: Int) {
        cond.lock()
        pendingSeek = (max(0, time), generation)
        cond.broadcast()
        cond.unlock()
    }

    /// Wake the pacing wait (the playhead moved / rate changed).
    func poke() { cond.lock(); cond.broadcast(); cond.unlock() }

    func stop() {
        cond.lock()
        stopped = true
        interrupted = true
        thread = nil
        cond.broadcast()
        cond.unlock()
    }

    private func dead(_ tok: Int) -> Bool { cond.lock(); defer { cond.unlock() }; return stopped || tok != token }

    private func takeSeek(_ tok: Int) -> (time: Double, generation: Int)? {
        cond.lock(); defer { cond.unlock() }
        guard !stopped, tok == token else { return nil }
        let s = pendingSeek; pendingSeek = nil; return s
    }

    private var hasPendingSeek: Bool { cond.lock(); defer { cond.unlock() }; return pendingSeek != nil }

    // MARK: thread

    private func run(_ tok: Int) {
        var attempts = 0
        var resumeAt: Double?
        var generation = 0
        while !dead(tok) {
            cond.lock()
            let source = self.source
            if let r = resumeAt, pendingSeek == nil { pendingSeek = (r, generation) }
            cond.unlock()
            guard let source else { return }
            let result = session(source, tok: tok, generation: &generation, lastTime: &resumeAt)
            switch result {
            case .stopped: return
            case .ended: onEnd?(generation); waitForSeekOrStop(tok); attempts = 0; resumeAt = nil
            case .failed(let msg):
                attempts += 1
                if attempts > 3 { onError?(msg); waitForSeekOrStop(tok); attempts = 0 }
                else { Thread.sleep(forTimeInterval: Double(attempts)) }
            }
        }
    }

    private func waitForSeekOrStop(_ tok: Int) {
        cond.lock()
        while !stopped, tok == token, pendingSeek == nil { cond.wait() }
        cond.unlock()
    }

    private enum Outcome { case stopped, ended, failed(String) }

    private static let errEOF: Int32 = -541_478_725     // AVERROR_EOF  (FFERRTAG('E','O','F',' '))
    private static let errAgain: Int32 = -35             // AVERROR(EAGAIN) on Darwin

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func session(_ source: Source, tok: Int, generation: inout Int, lastTime: inout Double?) -> Outcome {
        var fmt: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        guard fmt != nil else { return .failed("avformat_alloc_context") }
        var cb = AVIOInterruptCB()
        cb.opaque = Unmanaged.passUnretained(self).toOpaque()
        cb.callback = { ctx -> Int32 in
            guard let ctx else { return 0 }
            return Unmanaged<LiveAudioReader>.fromOpaque(ctx).takeUnretainedValue().interrupted ? 1 : 0
        }
        fmt?.pointee.interrupt_callback = cb

        var opts: OpaquePointer?
        var headers = source.headers
        if let ua = headers.removeValue(forKey: "User-Agent") ?? headers.removeValue(forKey: "user-agent") {
            av_dict_set(&opts, "user_agent", ua, 0)
        }
        if let ref = headers["Referer"] ?? headers["referer"] { av_dict_set(&opts, "referer", ref, 0) }
        if !headers.isEmpty {
            av_dict_set(&opts, "headers", headers.map { "\($0.key): \($0.value)\r\n" }.joined(), 0)
        }
        av_dict_set(&opts, "reconnect", "1", 0)
        av_dict_set(&opts, "reconnect_streamed", "1", 0)
        av_dict_set(&opts, "reconnect_delay_max", "4", 0)
        av_dict_set(&opts, "rw_timeout", "15000000", 0)
        av_dict_set(&opts, "probesize", "2000000", 0)
        av_dict_set(&opts, "analyzeduration", "2000000", 0)
        let urlString = source.url.isFileURL ? source.url.path : source.url.absoluteString
        let openErr = avformat_open_input(&fmt, urlString, nil, &opts)
        av_dict_free(&opts)
        guard openErr == 0, let ctx = fmt else { return dead(tok) ? .stopped : .failed("open \(openErr)") }
        defer {
            fmt?.pointee.interrupt_callback.opaque = nil
            fmt?.pointee.interrupt_callback.callback = nil
            avformat_close_input(&fmt)
        }
        guard avformat_find_stream_info(ctx, nil) >= 0 else { return dead(tok) ? .stopped : .failed("stream info") }

        var decoder: UnsafePointer<AVCodec>?
        let index = av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0)
        guard index >= 0, let decoder else { return .failed("no audio stream") }
        for i in 0 ..< Int(ctx.pointee.nb_streams) where i != Int(index) {
            ctx.pointee.streams[i]?.pointee.discard = AVDISCARD_ALL
        }
        guard let stream = ctx.pointee.streams[Int(index)] else { return .failed("stream") }
        var codec: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(decoder)
        defer { avcodec_free_context(&codec) }
        guard let codec, avcodec_parameters_to_context(codec, stream.pointee.codecpar) >= 0,
              avcodec_open2(codec, decoder, nil) >= 0 else { return .failed("decoder") }

        let tb = stream.pointee.time_base
        let tbSeconds = Double(tb.num) / Double(max(1, tb.den))
        let startOffset = ctx.pointee.start_time == Int64.min ? 0 : Double(ctx.pointee.start_time) / 1_000_000
        if ctx.pointee.duration > 0 { duration = Double(ctx.pointee.duration) / 1_000_000 }

        var swr: OpaquePointer?
        defer { swr_free(&swr) }
        var swrKey: (Int32, Int32, Int32) = (0, -1, 0)

        let pkt = av_packet_alloc()
        let frame = av_frame_alloc()
        defer { var p = pkt; av_packet_free(&p); var f = frame; av_frame_free(&f) }
        guard let pkt, let frame else { return .failed("alloc") }

        var pending: [Float] = []
        var pendingStart = 0.0
        var cursor: Double?             // media time of the next output sample
        var dropUntil = 0.0             // after a seek: discard audio before the exact target

        func flush() {
            guard !pending.isEmpty else { return }
            onPCM?(pending, pendingStart, generation)
            pendingStart += Double(pending.count) / 16000
            pending.removeAll(keepingCapacity: true)
        }

        func doSeek(_ t: Double, _ g: Int) {
            pending.removeAll(keepingCapacity: true)
            generation = g
            let ts = Int64((t + startOffset) * 1_000_000)
            av_seek_frame(ctx, -1, ts, 1 /* AVSEEK_FLAG_BACKWARD */)
            avcodec_flush_buffers(codec)
            if let swr { swr_init(swr) }
            cursor = nil
            dropUntil = t
        }

        while true {
            if dead(tok) { return .stopped }
            if let s = takeSeek(tok) { doSeek(s.time, s.generation) }
            // Pacing — stay ~lead seconds ahead of the playhead, never further.
            cond.lock()
            while !stopped, tok == token, pendingSeek == nil, !(shouldRun?() ?? true) { _ = cond.wait(until: Date().addingTimeInterval(0.1)) }
            cond.unlock()
            if dead(tok) { return .stopped }
            if hasPendingSeek { continue }
            if let c = cursor, let jump = skipTarget?(c), jump > c + 2 {
                flush(); doSeek(jump, generation); continue
            }

            let r = av_read_frame(ctx, pkt)
            if r < 0 {
                if dead(tok) { return .stopped }
                if r == Self.errEOF || ctx.pointee.pb?.pointee.eof_reached == 1 {
                    avcodec_send_packet(codec, nil)
                    flush()
                    return .ended
                }
                lastTime = cursor
                return .failed("read \(r)")
            }
            defer { av_packet_unref(pkt) }
            guard pkt.pointee.stream_index == index else { continue }
            guard avcodec_send_packet(codec, pkt) >= 0 else { continue }
            while avcodec_receive_frame(codec, frame) >= 0 {
                defer { av_frame_unref(frame) }
                let n = Int(frame.pointee.nb_samples)
                guard n > 0 else { continue }
                let channels = frame.pointee.ch_layout.nb_channels
                let key: (Int32, Int32, Int32) = (frame.pointee.sample_rate, frame.pointee.format, channels)
                if swr == nil || key != swrKey {
                    swr_free(&swr)
                    var outLayout = AVChannelLayout()
                    av_channel_layout_default(&outLayout, 1)
                    var inLayout = frame.pointee.ch_layout
                    swr_alloc_set_opts2(&swr, &outLayout, AV_SAMPLE_FMT_FLT, 16000, &inLayout,
                                        AVSampleFormat(rawValue: frame.pointee.format), frame.pointee.sample_rate, 0, nil)
                    guard swr != nil, swr_init(swr) >= 0 else { return .failed("swr") }
                    swrKey = key
                }
                let pts = frame.pointee.best_effort_timestamp
                let frameTime = pts == Int64.min ? (cursor ?? 0) : Double(pts) * tbSeconds - startOffset
                // Re-anchor on discontinuities (> 0.5 s) — keeps subtitle times on the player clock.
                if cursor == nil || abs(frameTime - (cursor ?? 0)) > 0.5 {
                    flush()
                    cursor = frameTime
                    pendingStart = frameTime
                }
                let maxOut = Int(swr_get_out_samples(swr, Int32(n))) + 32
                var out = [Float](repeating: 0, count: maxOut)
                let planes = av_sample_fmt_is_planar(AVSampleFormat(rawValue: frame.pointee.format)) != 0 ? Int(channels) : 1
                var inPtrs: [UnsafePointer<UInt8>?] = (0 ..< planes).map { UnsafePointer(frame.pointee.extended_data[$0]) }
                let got: Int32 = out.withUnsafeMutableBytes { raw in
                    var outPtrs: [UnsafeMutablePointer<UInt8>?] = [raw.baseAddress?.assumingMemoryBound(to: UInt8.self)]
                    return swr_convert(swr, &outPtrs, Int32(maxOut), &inPtrs, Int32(n))
                }
                guard got > 0 else { continue }
                var samples = Array(out.prefix(Int(got)))
                let chunkStart = cursor ?? frameTime
                cursor = chunkStart + Double(got) / 16000
                if chunkStart + Double(got) / 16000 <= dropUntil { pendingStart = cursor ?? 0; continue }
                if chunkStart < dropUntil {
                    let skip = min(samples.count, Int((dropUntil - chunkStart) * 16000))
                    samples.removeFirst(skip)
                    if pending.isEmpty { pendingStart = dropUntil }
                }
                dropUntil = 0
                if pending.isEmpty { pendingStart = (cursor ?? 0) - Double(samples.count) / 16000 }
                pending += samples
                if pending.count >= Self.chunkSamples { flush() }
            }
        }
    }
}
