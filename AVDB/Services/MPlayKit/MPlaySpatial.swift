//
//  MPlaySpatial.swift
//  AVDB
//
//  Build 353 full restoration, stage D: object-audio decoders.
//  Swift counterparts of the original's TrueHDObjectAudioDecoder /
//  DTSXObjectAudioDecoder (IOS-FINDINGS §2.4), each holding one
//  decoder handle and forwarding to the MPlayNative-style ABI
//  (MPlaySpatialBridge.h), which forwards to the pinned upstream
//  libraries (LibTrueHD @ 3eab2e7c, LibDTSX @ 6f0b321e — see
//  Spatial/UPSTREAM.md).
//
//  The upstream model is push bytes -> pull blocks until
//  NEED_MORE_DATA.  Block contents are owned by the decoder and
//  invalidated by the next pull/reset/destroy, so pull() copies
//  everything into Swift values (MPlayObjectBlock) synchronously.
//
//  Handles are not thread-safe (upstream contract): each wrapper
//  serialises on its own queue.  Rendering is constrained to
//  48 kHz by the renderer (MPlaySpatialRender.swift), per the
//  original's NOTICE adaptations; the decoders themselves run at
//  the stream's native rate.
//

import Foundation

/// One decoded element (bed channel, LFE, or object), unified
/// across both decoders' metadata shapes.
struct MPlayObjectElement {
    enum Kind {
        case bed, lfe, object, isf, unknown
    }
    var kind: Kind
    /// Shared speaker code space (TRUEHD_ATMOS_SPEAKER_*; DTSX uses
    /// the same values).  254 = object, 255 = unknown.
    var speaker: UInt8
    /// Room coordinates: x 0 left..1 right, y 0 front..1 back,
    /// z ear-level 0..1 ceiling (TrueHD allows -1..1; DTSX 0..1).
    var position: SIMD3<Float>
    /// Linear gain (DTS:X objects carry level in the PCM; gain = 1).
    var gain: Float
    var flags: UInt32
}

/// One decoded access unit / frame, fully copied out of the
/// decoder's ownership.
struct MPlayObjectBlock {
    var sampleRate: Int
    var frameCount: Int
    /// Planar PCM, one array per channel, normalised to [-1, 1).
    var channels: [[Float]]
    var speakers: [UInt8]
    var elements: [MPlayObjectElement]
    var pts: Int64
    var flags: UInt32
    var presentation: Int
}

private func copyChannels(_ channels: UnsafePointer<UnsafePointer<Float>?>?,
                          count: Int, frames: Int) -> [[Float]] {
    guard let channels, count > 0, frames > 0 else { return [] }
    return (0..<count).map { index in
        guard let plane = channels[index] else { return [Float](repeating: 0, count: frames) }
        return [Float](UnsafeBufferPointer(start: plane, count: frames))
    }
}

private func copySpeakers(_ speakers: UnsafePointer<UInt8>?, count: Int) -> [UInt8] {
    guard let speakers, count > 0 else { return [] }
    return [UInt8](UnsafeBufferPointer(start: speakers, count: count))
}

// MARK: - TrueHD

final class TrueHDObjectAudioDecoder {
    // 解码器结构体在上游头里只有前向声明、从不定义，Swift 导入器
    // 不为它生成具名类型（函数签名里的该指针会被替换成
    // OpaquePointer）；句柄按本仓 mpv 句柄的同一模式存 OpaquePointer。
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "avdb.mplaykit.spatial.truehd")

    /// presentation: TRUEHD_ATMOS_PRESENTATION_HIGHEST (-1) decodes
    /// the object presentation when present.
    init?(presentation: Int32 = -1) {
        handle = mplay_truehd_atmos_decoder_create(presentation)
        if handle == nil { return nil }
    }

    deinit {
        if let handle {
            mplay_truehd_atmos_decoder_destroy(handle)
        }
    }

    @discardableResult
    func reset() -> Int32 {
        queue.sync { mplay_truehd_atmos_decoder_reset(handle) }
    }

    @discardableResult
    func setPresentation(_ presentation: Int32) -> Int32 {
        queue.sync { mplay_truehd_atmos_decoder_set_presentation(handle, presentation) }
    }

    @discardableResult
    func push(_ data: Data, pts: Int64 = Int64.min) -> Int32 {
        queue.sync {
            guard let handle else { return TRUEHD_ATMOS_ERR_NULL }
            if data.isEmpty {
                return mplay_truehd_atmos_decoder_push(handle, nil, 0, pts)
            }
            return data.withUnsafeBytes { buffer in
                mplay_truehd_atmos_decoder_push(
                    handle,
                    buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count, pts
                )
            }
        }
    }

    /// One pull.  Status is the upstream code (0 = block returned,
    /// 1 = NEED_MORE_DATA, negative = error/refusal class).
    func pull() -> (status: Int32, block: MPlayObjectBlock?) {
        queue.sync {
            guard let handle else { return (TRUEHD_ATMOS_ERR_NULL, nil) }
            var raw = TrueHDAtmosBlock()
            let status = mplay_truehd_atmos_decoder_pull(handle, &raw)
            guard status == TRUEHD_ATMOS_OK else { return (status, nil) }
            return (status, Self.makeBlock(raw))
        }
    }

    var lastError: String {
        queue.sync {
            guard let handle, let text = mplay_truehd_atmos_decoder_last_error(handle)
            else { return "" }
            return String(cString: text)
        }
    }

    static func speakerName(_ speaker: UInt8) -> String {
        guard let text = mplay_truehd_atmos_speaker_name(speaker) else { return "?" }
        return String(cString: text)
    }

    private static func makeBlock(_ raw: TrueHDAtmosBlock) -> MPlayObjectBlock {
        let channelCount = Int(raw.channel_count)
        let frameCount = Int(raw.frame_count)
        var elements: [MPlayObjectElement] = []
        if raw.flags & TRUEHD_ATMOS_BLOCK_HAS_METADATA != 0,
           let metadata = raw.metadata?.pointee,
           let rawElements = metadata.elements {
            let count = Int(metadata.element_count)
            elements = (0..<count).map { index in
                let element = rawElements[index]
                let kind: MPlayObjectElement.Kind
                switch element.kind {
                case TRUEHD_ATMOS_ELEMENT_BED: kind = .bed
                case TRUEHD_ATMOS_ELEMENT_LFE: kind = .lfe
                case TRUEHD_ATMOS_ELEMENT_OBJECT: kind = .object
                case TRUEHD_ATMOS_ELEMENT_ISF: kind = .isf
                default: kind = .unknown
                }
                return MPlayObjectElement(
                    kind: kind,
                    speaker: element.speaker,
                    position: SIMD3<Float>(element.position.0, element.position.1, element.position.2),
                    gain: element.gain,
                    flags: element.flags
                )
            }
        }
        return MPlayObjectBlock(
            sampleRate: Int(raw.sample_rate),
            frameCount: frameCount,
            channels: copyChannels(raw.channels, count: channelCount, frames: frameCount),
            speakers: copySpeakers(raw.speakers, count: channelCount),
            elements: elements,
            pts: raw.pts,
            flags: raw.flags,
            presentation: Int(raw.presentation)
        )
    }
}

// MARK: - DTS:X

final class DTSXObjectAudioDecoder {
    // 同 TrueHD：前向声明的解码器结构体不生成 Swift 具名类型。
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "avdb.mplaykit.spatial.dtsx")

    init?() {
        handle = mplay_dtsx_decoder_create()
        if handle == nil { return nil }
    }

    deinit {
        if let handle {
            mplay_dtsx_decoder_destroy(handle)
        }
    }

    @discardableResult
    func reset() -> Int32 {
        queue.sync { mplay_dtsx_decoder_reset(handle) }
    }

    @discardableResult
    func push(_ data: Data, pts: Int64 = Int64.min) -> Int32 {
        queue.sync {
            guard let handle else { return DTSX_ERR_NULL }
            if data.isEmpty {
                return mplay_dtsx_decoder_push(handle, nil, 0, pts)
            }
            return data.withUnsafeBytes { buffer in
                mplay_dtsx_decoder_push(
                    handle,
                    buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    data.count, pts
                )
            }
        }
    }

    /// One pull.  Status 0 = block, 1 = NEED_MORE_DATA, -6/-7 =
    /// the stream is not (supported) DTS:X (sticky refusal).
    func pull() -> (status: Int32, block: MPlayObjectBlock?) {
        queue.sync {
            guard let handle else { return (DTSX_ERR_NULL, nil) }
            var raw = DTSXBlock()
            let status = mplay_dtsx_decoder_pull(handle, &raw)
            guard status == DTSX_OK else { return (status, nil) }
            return (status, Self.makeBlock(raw))
        }
    }

    var lastError: String {
        queue.sync {
            guard let handle, let text = mplay_dtsx_decoder_last_error(handle)
            else { return "" }
            return String(cString: text)
        }
    }

    static func presentationName(_ presentation: UInt32) -> String {
        guard let text = mplay_dtsx_presentation_name(presentation) else { return "?" }
        return String(cString: text)
    }

    private static func makeBlock(_ raw: DTSXBlock) -> MPlayObjectBlock {
        let channelCount = Int(raw.channel_count)
        let frameCount = Int(raw.frame_count)
        var elements: [MPlayObjectElement] = []
        if raw.flags & DTSX_BLOCK_HAS_METADATA != 0,
           let metadata = raw.metadata?.pointee,
           let rawElements = metadata.elements {
            let count = Int(metadata.element_count)
            elements = (0..<count).map { index in
                let element = rawElements[index]
                let kind: MPlayObjectElement.Kind
                switch element.kind {
                case DTSX_ELEMENT_BED: kind = .bed
                case DTSX_ELEMENT_LFE: kind = .lfe
                case DTSX_ELEMENT_OBJECT: kind = .object
                default: kind = .unknown
                }
                return MPlayObjectElement(
                    kind: kind,
                    speaker: element.speaker,
                    position: SIMD3<Float>(element.position.0, element.position.1, element.position.2),
                    gain: element.gain,
                    flags: element.flags
                )
            }
        }
        return MPlayObjectBlock(
            sampleRate: Int(raw.sample_rate),
            frameCount: frameCount,
            channels: copyChannels(raw.channels, count: channelCount, frames: frameCount),
            speakers: copySpeakers(raw.speakers, count: channelCount),
            elements: elements,
            pts: raw.pts,
            flags: raw.flags,
            presentation: Int(raw.presentation)
        )
    }
}

// MARK: - Facade (original: SpatialDecoder)

/// Picks the decoder for a codec and drains blocks per push.
final class MPlaySpatialDecoder {
    enum Codec {
        case trueHD
        case dtsX
    }

    let codec: Codec
    private let trueHD: TrueHDObjectAudioDecoder?
    private let dtsX: DTSXObjectAudioDecoder?

    init?(codec: Codec) {
        self.codec = codec
        switch codec {
        case .trueHD:
            trueHD = TrueHDObjectAudioDecoder()
            dtsX = nil
            if trueHD == nil { return nil }
        case .dtsX:
            trueHD = nil
            dtsX = DTSXObjectAudioDecoder()
            if dtsX == nil { return nil }
        }
    }

    @discardableResult
    func push(_ data: Data, pts: Int64 = Int64.min) -> Int32 {
        switch codec {
        case .trueHD: return trueHD?.push(data, pts: pts) ?? TRUEHD_ATMOS_ERR_NULL
        case .dtsX: return dtsX?.push(data, pts: pts) ?? DTSX_ERR_NULL
        }
    }

    /// Pull until NEED_MORE_DATA (or an error/refusal stops the loop).
    func drainBlocks() -> [MPlayObjectBlock] {
        var blocks: [MPlayObjectBlock] = []
        while true {
            let result: (status: Int32, block: MPlayObjectBlock?)
            switch codec {
            case .trueHD: result = trueHD?.pull() ?? (TRUEHD_ATMOS_ERR_NULL, nil)
            case .dtsX: result = dtsX?.pull() ?? (DTSX_ERR_NULL, nil)
            }
            guard result.status == 0, let block = result.block else { break }
            blocks.append(block)
        }
        return blocks
    }

    func reset() {
        trueHD?.reset()
        dtsX?.reset()
    }

    var lastError: String {
        trueHD?.lastError ?? dtsX?.lastError ?? ""
    }

    /// Both decoders' unwind selftests (the original's
    /// mplay_spatial_unwind_selftest).  Call once at app start in
    /// debug builds; a nonzero result means the Rust static/ dynamic
    /// link's unwinding is broken in this link configuration.
    static func unwindSelftest() -> Int32 {
        mplay_spatial_unwind_selftest()
    }
}
