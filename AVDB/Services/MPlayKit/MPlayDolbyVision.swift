//
//  MPlayDolbyVision.swift
//  AVDB
//
//  Build 353 full restoration (Dolby Vision, folded into stage C
//  per the user's 2026-11-23 decision): the original's DV surface
//  per IOS-FINDINGS §2.5/§3.2 —
//
//  - `DolbyP5ColorCorrection`: a Swift type in the original with
//    nested Matrix3 / Vector3 / RGB8 value types, a
//    `Map { yccToRGB, yccOffset, rgbToLMS }` with a static
//    `profile5`, and `convert(i:p:t:map:) -> RGB8` (all symbol-
//    original, IOS intermediates main_syms_demangled.txt).  Our
//    implementation mirrors that shape exactly.  The profile5
//    constants are the public ITU-R BT.2124 IPT constants (the
//    LMS<->IPT and BT.2020-RGB->LMS matrices), combined by matrix
//    inversion in code so the provenance is auditable.  The
//    original's baked Map.profile5 values were NOT extracted (that
//    would need disassembly, which the RE did not do), so numeric
//    identity with the original is not claimed — structure and
//    algorithm are aligned, constants are the public spec's.
//  - RPU parsing: see MPlayDoviRPU at the bottom of this file.
//  - FEL: the original registers CoreCustom `dovi-fel` /
//    `dovi-fel-hwdec` in its forked core (its demux/dovi_split.c +
//    the dovi_split bitstream filter compose the enhancement
//    layer).  Stock mpv 0.41 has no FEL composition — and even the
//    original falls back to base-layer rendering when its BSF is
//    unavailable (core log string, IOS intermediates).  Our FEL
//    landing is therefore the player-level surface: profile/level
//    read live from mpv's track properties
//    (track-list/N/dolby-vision-profile, -level — mpv 0.41
//    player/command.c), FEL presence inferred from profile 7
//    (mpv's property surface does not expose el_present_flag), and
//    the `dovi-fel-hwdec` marker as a player flag that pins the
//    decoder to the VideoToolbox path.  Dual-layer composition
//    itself is documented as not reproducible on stock mpv in
//    Build353-MPlayKit.md.
//

import Foundation

// MARK: - DolbyP5ColorCorrection (original type shape)

enum DolbyP5ColorCorrection {

    struct Matrix3 {
        var m00: Double, m01: Double, m02: Double
        var m10: Double, m11: Double, m12: Double
        var m20: Double, m21: Double, m22: Double

        func apply(_ v: Vector3) -> Vector3 {
            Vector3(
                x: m00 * v.x + m01 * v.y + m02 * v.z,
                y: m10 * v.x + m11 * v.y + m12 * v.z,
                z: m20 * v.x + m21 * v.y + m22 * v.z
            )
        }

        /// (self * other) — apply other first, then self.
        func multiplied(by other: Matrix3) -> Matrix3 {
            func row(_ a: (Double, Double, Double), _ b: Matrix3) -> (Double, Double, Double) {
                (a.0 * b.m00 + a.1 * b.m10 + a.2 * b.m20,
                 a.0 * b.m01 + a.1 * b.m11 + a.2 * b.m21,
                 a.0 * b.m02 + a.1 * b.m12 + a.2 * b.m22)
            }
            let r0 = row((m00, m01, m02), other)
            let r1 = row((m10, m11, m12), other)
            let r2 = row((m20, m21, m22), other)
            return Matrix3(m00: r0.0, m01: r0.1, m02: r0.2,
                           m10: r1.0, m11: r1.1, m12: r1.2,
                           m20: r2.0, m21: r2.1, m22: r2.2)
        }

        func inverted() -> Matrix3 {
            let det = m00 * (m11 * m22 - m12 * m21)
                    - m01 * (m10 * m22 - m12 * m20)
                    + m02 * (m10 * m21 - m11 * m20)
            let inv = 1.0 / det
            return Matrix3(
                m00: (m11 * m22 - m12 * m21) * inv,
                m01: (m02 * m21 - m01 * m22) * inv,
                m02: (m01 * m12 - m02 * m11) * inv,
                m10: (m12 * m20 - m10 * m22) * inv,
                m11: (m00 * m22 - m02 * m20) * inv,
                m12: (m02 * m10 - m00 * m12) * inv,
                m20: (m10 * m21 - m11 * m20) * inv,
                m21: (m01 * m20 - m00 * m21) * inv,
                m22: (m00 * m11 - m01 * m10) * inv
            )
        }
    }

    struct Vector3 {
        var x: Double, y: Double, z: Double

        static func - (a: Vector3, b: Vector3) -> Vector3 {
            Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
        }
    }

    struct RGB8 {
        var r: UInt8, g: UInt8, b: UInt8
    }

    struct Map {
        var yccToRGB: Matrix3
        var yccOffset: Vector3
        var rgbToLMS: Matrix3

        /// Profile 5's fixed map, built from the public BT.2124
        /// IPT constants (see the file header for provenance):
        ///   RGB(BT.2020) -> LMS and LMS -> IPT are the published
        ///   matrices; yccToRGB is their combined inverse
        ///   (IPT -> LMS -> RGB), yccOffset is zero (IPT is
        ///   already centred), rgbToLMS is the published matrix.
        static let profile5: Map = {
            let rgbToLMS = Matrix3(
                m00: 0.4120, m01: 0.5239, m02: 0.0641,
                m10: 0.1656, m11: 0.7206, m12: 0.1138,
                m20: 0.0600, m21: 0.2522, m22: 0.6878
            )
            let lmsToIPT = Matrix3(
                m00: 0.4000, m01: 0.4000, m02: 0.2000,
                m10: 4.4550, m11: -4.8510, m12: 0.3960,
                m20: 0.8056, m21: 0.3572, m22: -1.1628
            )
            let iptToRGB = rgbToLMS.inverted().multiplied(by: lmsToIPT.inverted())
            return Map(yccToRGB: iptToRGB,
                       yccOffset: Vector3(x: 0, y: 0, z: 0),
                       rgbToLMS: rgbToLMS)
        }()
    }

    static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    /// ST 2084 PQ EOTF for a normalised signal value:
    /// L = (max(N^(1/m2) − c1, 0) / (c2 − c3·N^(1/m2)))^(1/m1).
    private static func pqEOTF(_ n: Double) -> Double {
        let m1 = 0.1593017578125
        let m2 = 78.84375
        let c1 = 0.8359375
        let c2 = 18.8515625
        let c3 = 18.6875
        let np = pow(clamp01(n), 1.0 / m2)
        return pow(max(np - c1, 0) / (c2 - c3 * np), 1.0 / m1)
    }

    private static func sRGBEncode(_ linear: Double) -> Double {
        let x = clamp01(linear)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    /// One IPT pixel -> displayable sRGB.  i is intensity
    /// (0...1), p/t are the protan/tritan axes centred at 0
    /// (±0.5).  Steps: IPT -> BT.2020 RGB in the PQ domain via the
    /// map, PQ EOTF to linear, sRGB encode.  This is the CPU
    /// reference path; the post chain's pkDoviP5Kernel0 performs
    /// the same correction in the YUV domain on the GPU.
    static func convert(i: Double, p: Double, t: Double, map: Map) -> RGB8 {
        let ycc = Vector3(x: i, y: p, z: t) - map.yccOffset
        let rgbPQ = map.yccToRGB.apply(ycc)
        let r = sRGBEncode(pqEOTF(rgbPQ.x))
        let g = sRGBEncode(pqEOTF(rgbPQ.y))
        let b = sRGBEncode(pqEOTF(rgbPQ.z))
        return RGB8(r: UInt8((r * 255).rounded()),
                    g: UInt8((g * 255).rounded()),
                    b: UInt8((b * 255).rounded()))
    }
}

// MARK: - Player-facing DV state

/// Snapshot of the current stream's Dolby Vision state, read from
/// the player's track properties (see MPlayPlayer.dolbyVisionState).
struct MPlayDolbyVisionState {
    /// DV profile (5, 7, 8, ...) or nil when the stream is not DV.
    var profile: Int?
    var level: Int?
    /// FEL presence: inferred from profile 7 (dual-layer profile).
    /// mpv's property surface exposes profile/level only — the
    /// configuration record's el_present_flag is not reachable —
    /// so this is an inference, labelled as such wherever shown.
    var felPresent: Bool { profile == 7 }
    /// The `dovi-fel-hwdec` marker: the user/app asked for the FEL
    /// hardware-decode path (see MPlayPlayer.setDolbyVisionFELHardwareDecode).
    var felHardwareDecodeRequested: Bool = false
}

// MARK: - RPU parsing (MPlayDoviRPU)
//
// A stateless parser for one Dolby Vision RPU NAL unit.  The
// syntax implementation follows FFmpeg 8.0.1's
// libavcodec/dovi_rpudec.c field for field (that file was read
// directly when this parser was written; it is also the parser
// inside our own pipeline's FFmpeg).  Struct shapes are named
// after the original core's reflected C++ types (DoviReshapingCurve
// / DoviPolynomialCurve / DoviMMRCurve — IOS-FINDINGS §3.2); the
// original's DoviU16Data / DoviU64Data* names are its ABI's generic
// data containers and have no distinct syntax role, so they are
// not mirrored.  Scope limits, all deliberate and documented:
// - use_prev_vdr_rpu RPUs return header-only (resolving them needs
//   the previous RPU, i.e. parser state — the caller owns that).
// - linear_interp_flag polynomial segments are rejected, exactly
//   as FFmpeg does (AVERROR_PATCHWELCOME: undocumented, no samples).
// - DM extension blocks (L1/L2/...) are not decoded; the colour
//   metadata block itself (the Map source) is fully parsed.
// - The trailing CRC32 is not verified (FFmpeg only checks it
//   under AV_EF_CRCCHECK too).
// Any structural overrun or failed validation returns nil.

/// One polynomial reshaping segment (mapping_idc 0).
struct DoviPolynomialCurve {
    var order: Int
    /// Real-valued coefficients (order + 1 entries), already
    /// de-scaled from the fixed-point wire form.
    var coefficients: [Double]
}

/// One MMR reshaping segment (mapping_idc 1).
struct DoviMMRCurve {
    var order: Int
    var constant: Double
    /// [order][7] real-valued coefficients.
    var coefficients: [[Double]]
}

enum DoviMappingCurve {
    case polynomial(DoviPolynomialCurve)
    case mmr(DoviMMRCurve)
}

/// One component's reshaping curve (the original's
/// DoviReshapingCurve): pivot points are delta-coded on the wire
/// and stored here as the accumulated absolute values.
struct DoviReshapingCurve {
    var pivots: [UInt16] = []
    /// One entry per segment (pivots.count - 1).
    var curves: [DoviMappingCurve] = []
}

/// NLQ (nonlinear quantizer) parameters for one component.
struct DoviNLQParams {
    var offset: UInt64 = 0
    var vdrInMax: Double = 0
    /// Only present for method LINEAR_DZ (idc 1).
    var linearDeadzoneSlope: Double = 0
    var linearDeadzoneThreshold: Double = 0
}

/// The RPU's DM colour metadata — structurally the original's
/// DolbyP5ColorCorrection.Map plus the signal fields around it
/// (this block is where Map values come from on the wire).
struct MPlayDoviColorMetadata {
    var dmMetadataID: Int = 0
    var sceneRefreshFlag: Int = 0
    var map: DolbyP5ColorCorrection.Map
    var signalEOTF: Int = 0
    var signalEOTFParam0: Int = 0
    var signalEOTFParam1: Int = 0
    var signalEOTFParam2: UInt32 = 0
    var signalBitDepth: Int = 0
    var signalColorSpace: Int = 0
    var signalChromaFormat: Int = 0
    var signalFullRangeFlag: Int = 0
    var sourceMinPQ: Int = 0
    var sourceMaxPQ: Int = 0
    var sourceDiagonal: Int = 0
}

struct MPlayDoviRPU {
    var rpuType: Int = 0
    var rpuFormat: Int = 0
    var vdrRpuProfile: Int = 0
    var vdrRpuLevel: Int = 0
    var chromaResamplingExplicitFilterFlag: Bool = false
    /// 0 = fixed-point coefficients, 1 = float coefficients.
    var coefficientDataType: Int = 0
    var coefficientLog2Denom: Int = 0
    var vdrRpuNormalizedIdc: Int = 0
    var blVideoFullRangeFlag: Bool = false
    var blBitDepth: Int = 10
    var elBitDepth: Int = 10
    var vdrBitDepth: Int = 10
    var extMappingIdc: Int = 0
    var spatialResamplingFilterFlag: Bool = false
    var dmCompression: Int = 0
    var elSpatialResamplingFilterFlag: Bool = false
    var disableResidualFlag: Bool = false
    var usePrevVdrRpu: Bool = false
    var vdrRpuID: Int = 0
    var mappingColorSpace: Int = 0
    var mappingChromaFormatIdc: Int = 0
    /// Three components; empty when usePrevVdrRpu is set.
    var components: [DoviReshapingCurve] = []
    /// -1 when NLQ is not used; 0 = NONE, 1 = LINEAR_DZ.
    var nlqMethodIdc: Int = -1
    var nlqPivots: [UInt16] = []
    var nlq: [DoviNLQParams] = []
    var numXPartitions: Int = 0
    var numYPartitions: Int = 0
    var colorMetadata: MPlayDoviColorMetadata?

    /// Parse one RPU.  `data` starts at the NAL unit (an Annex-B
    /// start code, if present, is skipped; emulation-prevention
    /// bytes are stripped).  Returns nil on any structural failure.
    static func parse(_ data: Data) -> MPlayDoviRPU? {
        var bytes = [UInt8](data)
        if bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 1 {
            bytes.removeFirst(4)
        } else if bytes.count >= 3, bytes[0] == 0, bytes[1] == 0, bytes[2] == 1 {
            bytes.removeFirst(3)
        }
        // RBSP emulation prevention: 00 00 03 -> 00 00.
        var rbsp: [UInt8] = []
        rbsp.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index + 2 < bytes.count, bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 3 {
                rbsp.append(0)
                rbsp.append(0)
                index += 3
            } else {
                rbsp.append(bytes[index])
                index += 1
            }
        }
        guard !rbsp.isEmpty, rbsp[0] == 25 else { return nil }  // rpu_nal_prefix
        var reader = MPlayRPUReader(bytes: rbsp)
        reader.skipBits(8)
        return parseBody(&reader)
    }

    private static func parseBody(_ reader: inout MPlayRPUReader) -> MPlayDoviRPU? {
        var rpu = MPlayDoviRPU()
        rpu.rpuType = Int(reader.bits(6))
        guard rpu.rpuType == 2, !reader.failed else { return nil }
        rpu.rpuFormat = Int(reader.bits(11))
        rpu.vdrRpuProfile = Int(reader.bits(4))
        rpu.vdrRpuLevel = Int(reader.bits(4))
        guard reader.bit() else { return nil }  // vdr_seq_info_present (FFmpeg: required)
        rpu.chromaResamplingExplicitFilterFlag = reader.bit()
        rpu.coefficientDataType = Int(reader.bits(2))
        guard rpu.coefficientDataType <= 1, !reader.failed else { return nil }
        if rpu.coefficientDataType == 0 {
            rpu.coefficientLog2Denom = reader.ue()
            guard (13...32).contains(rpu.coefficientLog2Denom) else { return nil }
        } else {
            rpu.coefficientLog2Denom = 32
        }
        reader.denom = rpu.coefficientLog2Denom
        reader.dataType = rpu.coefficientDataType
        rpu.vdrRpuNormalizedIdc = Int(reader.bits(2))
        rpu.blVideoFullRangeFlag = reader.bit()
        guard rpu.rpuFormat & 0x700 == 0 else { return nil }  // unsupported format space
        let blMinus8 = reader.ue()
        let elMinus8Raw = reader.ue()
        let vdrMinus8 = reader.ue()
        guard blMinus8 <= 8, vdrMinus8 <= 8, (elMinus8Raw & 0xFF) <= 8, !reader.failed
        else { return nil }
        rpu.blBitDepth = blMinus8 + 8
        rpu.elBitDepth = (elMinus8Raw & 0xFF) + 8
        rpu.extMappingIdc = elMinus8Raw >> 8
        rpu.vdrBitDepth = vdrMinus8 + 8
        rpu.spatialResamplingFilterFlag = reader.bit()
        rpu.dmCompression = Int(reader.bits(3))
        rpu.elSpatialResamplingFilterFlag = reader.bit()
        rpu.disableResidualFlag = reader.bit()
        let dmPresent = reader.bit()
        guard !reader.failed else { return nil }
        guard rpu.dmCompression <= 1 else { return nil }       // no device supports > 1
        guard !(rpu.dmCompression > 0 && !dmPresent) else { return nil }
        rpu.usePrevVdrRpu = reader.bit()
        let useNLQ = !rpu.disableResidualFlag
        if rpu.vdrRpuProfile == 5, useNLQ { return nil }       // P5 RPUs never use NLQ
        if rpu.usePrevVdrRpu {
            rpu.vdrRpuID = reader.ue()
            guard !reader.failed else { return nil }
            return rpu  // header-only; caller resolves the referenced mapping
        }
        rpu.vdrRpuID = reader.ue()
        rpu.mappingColorSpace = reader.ue()
        rpu.mappingChromaFormatIdc = reader.ue()
        guard !reader.failed else { return nil }

        var pivotCounts: [Int] = []
        for _ in 0..<3 {
            let numPivotsMinus2 = reader.ue()
            guard numPivotsMinus2 <= 15, !reader.failed else { return nil }
            let numPivots = numPivotsMinus2 + 2
            pivotCounts.append(numPivots)
            var curve = DoviReshapingCurve()
            var pivot = 0
            for _ in 0..<numPivots {
                pivot += Int(reader.bits(rpu.blBitDepth))
                curve.pivots.append(UInt16(min(pivot, 0xFFFF)))
            }
            rpu.components.append(curve)
        }

        if useNLQ {
            rpu.nlqMethodIdc = Int(reader.bits(3))
            guard rpu.nlqMethodIdc <= 1, !reader.failed else { return nil }
            var nlqPivot = 0
            for _ in 0..<2 {
                nlqPivot += Int(reader.bits(rpu.blBitDepth))
                rpu.nlqPivots.append(UInt16(min(nlqPivot, 0xFFFF)))
            }
        }
        rpu.numXPartitions = reader.ue() + 1
        rpu.numYPartitions = reader.ue() + 1
        guard !reader.failed else { return nil }

        for component in 0..<3 {
            let segments = pivotCounts[component] - 1
            for _ in 0..<segments {
                let mappingIdc = reader.ue()
                guard mappingIdc <= 1, !reader.failed else { return nil }
                if mappingIdc == 0 {
                    let orderMinus1 = reader.ue()
                    guard orderMinus1 <= 1 else { return nil }
                    if orderMinus1 == 0 {
                        // linear_interp_flag: FFmpeg rejects it
                        // (undocumented); so do we.
                        guard !reader.bit() else { return nil }
                    }
                    var coefficients: [Double] = []
                    for _ in 0...orderMinus1 + 1 {
                        coefficients.append(reader.seCoef())
                    }
                    rpu.components[component].curves.append(
                        .polynomial(DoviPolynomialCurve(order: orderMinus1 + 1,
                                                        coefficients: coefficients)))
                } else {
                    let orderMinus1 = Int(reader.bits(2))
                    guard orderMinus1 <= 2 else { return nil }
                    let constant = reader.seCoef()
                    var rows: [[Double]] = []
                    for _ in 0..<orderMinus1 + 1 {
                        var row: [Double] = []
                        for _ in 0..<7 {
                            row.append(reader.seCoef())
                        }
                        rows.append(row)
                    }
                    rpu.components[component].curves.append(
                        .mmr(DoviMMRCurve(order: orderMinus1 + 1,
                                          constant: constant, coefficients: rows)))
                }
            }
        }
        guard !reader.failed else { return nil }

        if useNLQ {
            for _ in 0..<3 {
                var params = DoviNLQParams()
                params.offset = reader.bits(rpu.elBitDepth)
                params.vdrInMax = reader.ueCoef()
                if rpu.nlqMethodIdc == 1 {
                    params.linearDeadzoneSlope = reader.ueCoef()
                    params.linearDeadzoneThreshold = reader.ueCoef()
                }
                rpu.nlq.append(params)
            }
            guard !reader.failed else { return nil }
        }

        if dmPresent {
            let affected = reader.ue()
            let current = reader.ue()
            guard affected == current, !reader.failed else { return nil }
            var meta = MPlayDoviColorMetadata(
                map: DolbyP5ColorCorrection.Map(
                    yccToRGB: DolbyP5ColorCorrection.Matrix3(
                        m00: 0, m01: 0, m02: 0, m10: 0, m11: 0, m12: 0, m20: 0, m21: 0, m22: 0),
                    yccOffset: DolbyP5ColorCorrection.Vector3(x: 0, y: 0, z: 0),
                    rgbToLMS: DolbyP5ColorCorrection.Matrix3(
                        m00: 0, m01: 0, m02: 0, m10: 0, m11: 0, m12: 0, m20: 0, m21: 0, m22: 0))
            )
            meta.dmMetadataID = affected
            meta.sceneRefreshFlag = reader.ue()
            if rpu.dmCompression == 0 {
                var ycc = [Double](repeating: 0, count: 9)
                for k in 0..<9 { ycc[k] = Double(reader.sbits(16)) / 8192.0 }
                var offsets = [Double](repeating: 0, count: 3)
                let offsetDenom = Double(1 << (rpu.vdrRpuProfile == 4 ? 30 : 28))
                for k in 0..<3 { offsets[k] = Double(reader.bits(32)) / offsetDenom }
                var lms = [Double](repeating: 0, count: 9)
                for k in 0..<9 { lms[k] = Double(reader.sbits(16)) / 16384.0 }
                meta.map = DolbyP5ColorCorrection.Map(
                    yccToRGB: DolbyP5ColorCorrection.Matrix3(
                        m00: ycc[0], m01: ycc[1], m02: ycc[2],
                        m10: ycc[3], m11: ycc[4], m12: ycc[5],
                        m20: ycc[6], m21: ycc[7], m22: ycc[8]),
                    yccOffset: DolbyP5ColorCorrection.Vector3(
                        x: offsets[0], y: offsets[1], z: offsets[2]),
                    rgbToLMS: DolbyP5ColorCorrection.Matrix3(
                        m00: lms[0], m01: lms[1], m02: lms[2],
                        m10: lms[3], m11: lms[4], m12: lms[5],
                        m20: lms[6], m21: lms[7], m22: lms[8]))
                meta.signalEOTF = Int(reader.bits(16))
                meta.signalEOTFParam0 = Int(reader.bits(16))
                meta.signalEOTFParam1 = Int(reader.bits(16))
                meta.signalEOTFParam2 = UInt32(reader.bits(32))
                meta.signalBitDepth = Int(reader.bits(5))
                guard (8...16).contains(meta.signalBitDepth) else { return nil }
                meta.signalColorSpace = Int(reader.bits(2))
                meta.signalChromaFormat = Int(reader.bits(2))
                meta.signalFullRangeFlag = Int(reader.bits(2))
                meta.sourceMinPQ = Int(reader.bits(12))
                meta.sourceMaxPQ = Int(reader.bits(12))
                meta.sourceDiagonal = Int(reader.bits(10))
            }
            guard !reader.failed else { return nil }
            // Extension blocks are not decoded (see header).
            rpu.colorMetadata = meta
        }
        return rpu
    }
}

/// MSB-first bit reader with Exp-Golomb and the RPU coefficient
/// readers, mirroring FFmpeg's GetBitContext helpers.
private struct MPlayRPUReader {
    let bytes: [UInt8]
    var bitPosition = 0
    var failed = false
    var denom = 23
    var dataType = 0

    mutating func bits(_ count: Int) -> UInt64 {
        guard count > 0 else { return 0 }
        var value: UInt64 = 0
        for _ in 0..<count {
            let byteIndex = bitPosition / 8
            guard byteIndex < bytes.count else {
                failed = true
                return value
            }
            let bit = (bytes[byteIndex] >> (7 - bitPosition % 8)) & 1
            value = (value << 1) | UInt64(bit)
            bitPosition += 1
        }
        return value
    }

    mutating func skipBits(_ count: Int) {
        _ = bits(count)
    }

    mutating func bit() -> Bool {
        bits(1) == 1
    }

    mutating func sbits(_ count: Int) -> Int {
        let raw = bits(count)
        let shift = 64 - count
        return Int(Int64(bitPattern: raw << shift) >> shift)
    }

    /// Unsigned Exp-Golomb (leading-zero cap 31, as ue_golomb_31).
    mutating func ue() -> Int {
        var zeros = 0
        while !failed {
            if bit() { break }
            zeros += 1
            guard zeros <= 31 else {
                failed = true
                return 0
            }
        }
        if zeros == 0 { return 0 }
        return (1 << zeros) - 1 + Int(bits(zeros))
    }

    /// Signed Exp-Golomb.
    mutating func se() -> Int {
        let code = ue()
        if code % 2 == 1 { return (code + 1) / 2 }
        return -code / 2
    }

    /// get_ue_coef: unsigned coefficient -> real value.
    mutating func ueCoef() -> Double {
        if dataType == 1 {
            return Double(Float(bitPattern: UInt32(bits(32))))
        }
        let ipart = ue()
        let frac = bits(denom)
        let scaled = (Int64(ipart) << denom) | Int64(frac)
        return Double(scaled) / Double(1 << denom)
    }

    /// get_se_coef: signed coefficient -> real value (the wire
    /// form is (int << denom) | frac, exactly as FFmpeg composes it).
    mutating func seCoef() -> Double {
        if dataType == 1 {
            return Double(Float(bitPattern: UInt32(bits(32))))
        }
        let ipart = se()
        let frac = bits(denom)
        let scaled = (Int64(ipart) << denom) | Int64(frac)
        return Double(scaled) / Double(1 << denom)
    }
}
