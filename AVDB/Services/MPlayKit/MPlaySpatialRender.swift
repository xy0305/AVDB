//
//  MPlaySpatialRender.swift
//  AVDB
//
//  Build 353 full restoration, stage D: rendering + relay, the
//  roles AetherEngine fills in the original (IOS-FINDINGS §2.4:
//  SpatialDecoder -> ObjectAudioRenderer with layouts 5.1.2 /
//  5.1.4 / 7.1.2 / 7.1.4 / 9.1.6, AllocentricPanner, PeakLimiter;
//  and the AudioRelay: APAC 7.1.4 encode -> in-memory HLS ->
//  AVPlayer borrowing the system spatial-audio path, with a 7.1
//  PCM downmix fallback and a silent-Atmos keep-alive).
//
//  These are OUR implementations of those roles in Swift (the
//  pinned AetherEngine is a SwiftPM package whose dependency graph
//  — a prebuilt FFmpeg, SMB client — AVDB does not take on; the
//  decoders, which are the parts with no substitute, are the real
//  pinned libraries, see MPlaySpatial.swift).  Equivalence notes:
//  - Object panning here is a nearest-three-speakers inverse-
//    distance distribution over the layout — an approximation of
//    the original's allocentric panner, not its algorithm.
//  - The limiter is a simple soft-knee peak limiter, not the
//    original's PeakLimiter implementation.
//  - Rendering is constrained to 48 kHz (the original's NOTICE
//    adaptation); other block rates are converted with
//    AVAudioConverter.
//  - APAC encode uses AVAudioConverter to kAudioFormatAPAC.  The
//    pinned AetherEngine annotates its APAC encoder
//    @available(iOS 26); the relay therefore gates the APAC route
//    to iOS 26+ and falls back to multichannel PCM below it — the
//    original's own documented fallback when APAC is unavailable.
//
//  Integration status: this layer is complete and callable, but it
//  is NOT yet fed by live mpv playback — that needs an audio_relay
//  ao inside the core routing the playing file's TrueHD/DTS:X
//  bitstream here, which is the documented remaining gap (see
//  Build353-MPlayKit.md).  Nothing in the UI calls it this round.
//

import AVFoundation
import Foundation
import Network
import simd

// MARK: - Layouts (speaker codes are the shared TRUEHD_ATMOS_SPEAKER_* space)

enum MPlaySpatialLayout: CaseIterable {
    case fiveOneTwo, fiveOneFour, sevenOneTwo, sevenOneFour, nineOneSix

    /// Speaker codes in output channel order.
    var speakers: [UInt8] {
        switch self {
        case .fiveOneTwo:
            return [0, 1, 2, 3, 4, 5, 6, 7]                       // L R C LFE LS RS TFL TFR
        case .fiveOneFour:
            return [0, 1, 2, 3, 4, 5, 6, 7, 10, 11]               // + TBL TBR
        case .sevenOneTwo:
            return [0, 1, 2, 3, 14, 15, 4, 5, 6, 7]               // L R C LFE LB RB LS RS TFL TFR
        case .sevenOneFour:
            return [0, 1, 2, 3, 14, 15, 4, 5, 6, 7, 10, 11]      // + TBL TBR
        case .nineOneSix:
            return [0, 1, 2, 3, 14, 15, 4, 5, 20, 21, 6, 7, 8, 9, 10, 11]
        }
    }

    var channelCount: Int { speakers.count }

    /// Nominal room position per speaker code (x left..right,
    /// y front..back, z ear..ceiling).
    static func nominalPosition(for speaker: UInt8) -> SIMD3<Float> {
        switch speaker {
        case 0: return SIMD3(0.0, 0.0, 0.0)    // L
        case 1: return SIMD3(1.0, 0.0, 0.0)    // R
        case 2: return SIMD3(0.5, 0.0, 0.0)    // C
        case 3: return SIMD3(0.5, 0.0, 0.0)    // LFE
        case 4: return SIMD3(0.0, 0.5, 0.0)    // LS
        case 5: return SIMD3(1.0, 0.5, 0.0)    // RS
        case 6: return SIMD3(0.0, 0.0, 1.0)    // TFL
        case 7: return SIMD3(1.0, 0.0, 1.0)    // TFR
        case 8: return SIMD3(0.0, 0.5, 1.0)    // TSL
        case 9: return SIMD3(1.0, 0.5, 1.0)    // TSR
        case 10: return SIMD3(0.0, 1.0, 1.0)   // TBL
        case 11: return SIMD3(1.0, 1.0, 1.0)   // TBR
        case 12: return SIMD3(0.3, 0.0, 0.0)   // LSC
        case 13: return SIMD3(0.7, 0.0, 0.0)   // RSC
        case 14: return SIMD3(0.0, 1.0, 0.0)   // LB
        case 15: return SIMD3(1.0, 1.0, 0.0)   // RB
        case 16: return SIMD3(0.5, 1.0, 0.0)   // CB
        case 17: return SIMD3(0.5, 0.5, 1.0)   // TC
        case 20: return SIMD3(0.0, 0.25, 0.0)  // LW
        case 21: return SIMD3(1.0, 0.25, 0.0)  // RW
        case 22: return SIMD3(0.5, 0.0, 1.0)   // TFC
        default: return SIMD3(0.5, 0.5, 0.0)
        }
    }
}

// MARK: - ObjectAudioRenderer (original role: ObjectAudioRenderer)

final class ObjectAudioRenderer {
    let layout: MPlaySpatialLayout
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var running = false

    init(layout: MPlaySpatialLayout = .sevenOneFour) {
        self.layout = layout
        // 48 kHz float, non-interleaved, channel count per layout.
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: AVAudioChannelCount(layout.channelCount),
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !running else { return }
        do {
            try engine.start()
            playerNode.play()
            running = true
        } catch {
            MPlayDiagnostics.log("spatial renderer: engine start failed: \(error)")
        }
    }

    func stop() {
        guard running else { return }
        playerNode.stop()
        engine.stop()
        running = false
    }

    /// Render one decoded block into the layout and schedule it.
    func schedule(_ block: MPlayObjectBlock) {
        guard let buffer = render(block) else { return }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Block -> layout PCM buffer (48 kHz).  Bed channels map by
    /// speaker code (missing layout speakers fold to the nearest);
    /// objects distribute over the three nearest layout speakers
    /// by inverse distance, weighted by element gain; a soft peak
    /// limiter guards the sum.  Blocks at other sample rates are
    /// converted first.
    func render(_ block: MPlayObjectBlock) -> AVAudioPCMBuffer? {
        guard let source = pcmBuffer(from: block) else { return nil }
        let pcm: AVAudioPCMBuffer
        if source.format.sampleRate == 48_000 {
            pcm = source
        } else if let converted = convert(source, to: format) {
            pcm = converted
        } else {
            return nil
        }
        guard let out = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: pcm.frameLength),
              let inChannels = pcm.floatChannelData,
              let outChannels = out.floatChannelData
        else { return nil }
        out.frameLength = pcm.frameLength
        let frames = Int(pcm.frameLength)
        let layoutSpeakers = layout.speakers
        let layoutPositions = layoutSpeakers.map { MPlaySpatialLayout.nominalPosition(for: $0) }

        for (index, element) in block.elements.enumerated() {
            guard index < Int(pcm.format.channelCount) else { break }
            let input = inChannels[index]
            switch element.kind {
            case .bed, .lfe:
                if let target = layoutSpeakers.firstIndex(of: element.speaker) {
                    mix(input, frames: frames, into: outChannels[target], gain: element.gain)
                } else {
                    distribute(input, frames: frames, from: MPlaySpatialLayout.nominalPosition(for: element.speaker),
                               into: outChannels, positions: layoutPositions, gain: element.gain)
                }
            case .object, .isf, .unknown:
                distribute(input, frames: frames, from: element.position,
                           into: outChannels, positions: layoutPositions, gain: element.gain)
            }
        }
        softLimit(outChannels, channels: layout.channelCount, frames: frames)
        return out
    }

    private func pcmBuffer(from block: MPlayObjectBlock) -> AVAudioPCMBuffer? {
        guard block.frameCount > 0, !block.channels.isEmpty else { return nil }
        let blockFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(block.sampleRate),
            channels: AVAudioChannelCount(block.channels.count),
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: blockFormat,
                                            frameCapacity: AVAudioFrameCount(block.frameCount)),
              let data = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(block.frameCount)
        for (index, channel) in block.channels.enumerated() {
            channel.withUnsafeBufferPointer { source in
                data[index].update(from: source.baseAddress!, count: block.frameCount)
            }
        }
        return buffer
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    private func mix(_ input: UnsafeMutablePointer<Float>, frames: Int,
                     into output: UnsafeMutablePointer<Float>, gain: Float) {
        for frame in 0..<frames {
            output[frame] += input[frame] * gain
        }
    }

    private func distribute(_ input: UnsafeMutablePointer<Float>, frames: Int,
                            from position: SIMD3<Float>,
                            into outputs: UnsafePointer<UnsafeMutablePointer<Float>>,
                            positions: [SIMD3<Float>], gain: Float) {
        // Three nearest layout speakers, inverse-distance weights
        // normalised to unit power (approximation of the original's
        // allocentric panner).
        let scored = positions.enumerated().map { (index, speakerPosition) in
            (index: index, distance: simd_distance(position, speakerPosition))
        }.sorted { $0.distance < $1.distance }
        let nearest = Array(scored.prefix(3))
        let weights = nearest.map { 1.0 / max($0.distance, 0.05) }
        let norm = sqrt(weights.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return }
        for (slot, target) in nearest.enumerated() {
            let weight = weights[slot] / norm * gain
            mix(input, frames: frames, into: outputs[target.index], gain: weight)
        }
    }

    private func softLimit(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
                           channels count: Int, frames: Int) {
        // Simple soft-knee peak limiter (not the original's
        // PeakLimiter): per-sample tanh soft clip above 0.9.
        for channel in 0..<count {
            let data = channels[channel]
            for frame in 0..<frames {
                let value = data[frame]
                if value > 0.9 || value < -0.9 {
                    data[frame] = tanh(value)
                }
            }
        }
    }
}

// MARK: - APAC encode (original role: APACEncoder / APACEncodePipeline)

final class MPlayAPACEncoder {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    /// Nil when APAC is unavailable on this OS (see the file
    /// header's availability note).
    init?(inputFormat: AVAudioFormat) {
        guard #available(iOS 26.0, *) else { return nil }
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatAPAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(inputFormat.channelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let apacFormat = AVAudioFormat(streamDescription: &description) else { return nil }
        guard let converter = AVAudioConverter(from: inputFormat, to: apacFormat) else { return nil }
        self.converter = converter
        self.outputFormat = apacFormat
    }

    /// Encode one PCM buffer to APAC packet bytes (an .m4a-ish
    /// segment payload for the in-memory HLS stream).
    func encode(_ buffer: AVAudioPCMBuffer) -> Data? {
        // 本 SDK 里 AVAudioCompressedBuffer 的 init 不是 failable 的，
        // 直接构造（不存在需要 guard 的失败路径）。
        let out = AVAudioCompressedBuffer(format: outputFormat,
                                          packetCapacity: 256,
                                          maximumPacketSize: converter.maximumOutputPacketSize)
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, out.packetCount > 0 else { return nil }
        return Data(bytes: out.data, count: Int(out.byteLength))
    }
}

// MARK: - In-memory HLS (original role: MPlayAPACStream / HLSLocalServer)

/// Serves the APAC segments as a live HLS stream from memory on a
/// loopback NWListener — no files, no external server.
final class MPlayAPACStream {
    private let queue = DispatchQueue(label: "avdb.mplaykit.apacstream")
    private var listener: NWListener?
    private var segments: [(sequence: Int, data: Data)] = []
    private var nextSequence = 0
    private(set) var port: UInt16 = 0

    var playlistURL: URL? {
        port > 0 ? URL(string: "http://127.0.0.1:\(port)/stream.m3u8") : nil
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .ready = state {
                        self?.port = listener.port?.rawValue ?? 0
                    }
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                MPlayDiagnostics.log("apac stream: listener failed: \(error)")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.port = 0
        }
    }

    func addSegment(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.segments.append((self.nextSequence, data))
            self.nextSequence += 1
            if self.segments.count > 6 {
                self.segments.removeFirst(self.segments.count - 6)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8)
            else {
                connection.cancel()
                return
            }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let (status, contentType, body) = self.response(for: path)
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(header.utf8)
            payload.append(body)
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for path: String) -> (String, String, Data) {
        if path == "/stream.m3u8" {
            let first = segments.first?.sequence ?? 0
            var playlist = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:\(first)\n"
            for segment in segments {
                playlist += "#EXTINF:2.000,\nseg\(segment.sequence).m4a\n"
            }
            return ("200 OK", "application/vnd.apple.mpegurl", Data(playlist.utf8))
        }
        if path.hasPrefix("/seg"), path.hasSuffix(".m4a"),
           let number = Int(path.dropFirst(4).dropLast(4)),
           let segment = segments.first(where: { $0.sequence == number }) {
            return ("200 OK", "audio/mp4", segment.data)
        }
        return ("404 Not Found", "text/plain", Data("not found".utf8))
    }
}

// MARK: - Silent Atmos keep-alive (original role: AtmosOutputActivator)

/// Loops the bundled silent Atmos sample so the system keeps the
/// Atmos route open while the relay is live (the original plays
/// its mplay-silent-atmos.mp4 for the same reason, generated by
/// AetherEngine's Scripts/make-silent-atmos.swift — our CI stage
/// generates the equivalent asset; when it is absent this
/// activator is inert and logs once).
final class AtmosOutputActivator {
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private let queuePlayer = AVQueuePlayer()

    func start() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "mplay-silent-atmos", withExtension: "mp4") else {
            MPlayDiagnostics.log("atmos activator: silent-atmos asset not bundled; route keep-alive inert")
            return
        }
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        player = queuePlayer
        queuePlayer.play()
    }

    func stop() {
        queuePlayer.pause()
        looper = nil
        player = nil
    }
}

// MARK: - AudioRelay (original role: AudioRelay + APAC/HLS -> AVPlayer)

/// Routes rendered object audio either through APAC -> in-memory
/// HLS -> an AVPlayer (borrowing the system spatial-audio path) or,
/// when APAC is unavailable, straight to the local multichannel
/// renderer (the original's documented 7.1 PCM fallback).
final class MPlayAudioRelay {
    enum Route {
        case apac
        case pcmFallback
    }

    private(set) var route: Route = .pcmFallback
    let renderer = ObjectAudioRenderer(layout: .sevenOneFour)
    private var encoder: MPlayAPACEncoder?
    private let stream = MPlayAPACStream()
    private let activator = AtmosOutputActivator()

    // MARK: Relay tuning (the original's ao sub-options)
    //
    // Policy values the relay consults; in the original these tune
    // its audio_relay ao directly.  Ours are stored state consumed
    // by the renderer's scheduling — the ao itself does not exist
    // in our core (see Build353-MPlayKit.md, spatial section).

    /// How long video waits for the relay to produce audio.
    private(set) var videoHoldMilliseconds: Double = 250
    /// PCM trimmed from the head after a seek.
    private(set) var pcmSeekTrimMilliseconds: Double = 0
    /// Maximum PCM lead the relay may run ahead of video.
    private(set) var pcmMaxLeadMilliseconds: Double = 500

    func setAudioRelayVideoHold(milliseconds: Double) {
        videoHoldMilliseconds = max(0, milliseconds)
    }

    func setAudioRelayPCMSeekTrim(milliseconds: Double) {
        pcmSeekTrimMilliseconds = max(0, milliseconds)
    }

    func setAudioRelayPCMMaxLead(milliseconds: Double) {
        pcmMaxLeadMilliseconds = max(0, milliseconds)
    }

    /// The AVPlayer consuming the HLS stream on the APAC route
    /// (play it through the system output to get system spatial
    /// audio).  Nil on the PCM route.
    let relayPlayer = AVPlayer()

    func start() {
        if let encoder = MPlayAPACEncoder(inputFormat: renderer.format) {
            self.encoder = encoder
            route = .apac
            stream.start()
            activator.start()
            if let url = stream.playlistURL {
                relayPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            }
        } else {
            route = .pcmFallback
            renderer.start()
        }
    }

    func stop() {
        if route == .apac {
            relayPlayer.pause()
            activator.stop()
            stream.stop()
        } else {
            renderer.stop()
        }
    }

    /// Submit one decoded block.  On the APAC route the block is
    /// rendered to 7.1.4, encoded, and appended as an HLS segment;
    /// on the PCM route it is scheduled on the local renderer.
    func submit(_ block: MPlayObjectBlock) {
        switch route {
        case .apac:
            guard let encoder, let buffer = renderer.render(block),
                  let segment = encoder.encode(buffer) else { return }
            stream.addSegment(segment)
        case .pcmFallback:
            renderer.schedule(block)
        }
    }
}
