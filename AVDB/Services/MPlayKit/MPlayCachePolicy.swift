//
//  MPlayCachePolicy.swift
//  AVDB
//
//  Build 353 full restoration, stage D: the cache policy model.
//  The original's cache is a segmented model —
//  CachePolicy{capacity, directory, prefetchBytes, seconds,
//  segmentBytes, segments} (IOS-FINDINGS §2.5/§3.2) — whose concrete
//  values are code constants with no string trace and are therefore
//  UNRECOVERABLE.  This struct reproduces the model's structure and
//  field names exactly; the values are ours (marked as such
//  everywhere they surface) and must never be cited as the
//  original's parameters.
//
//  Mapping to mpv options (approximate by construction — mpv's
//  demuxer cache is a byte-capped ring, not a segmented store):
//    capacity      -> demuxer-max-bytes (segments * segmentBytes,
//                     normalised to capacity by the standard policy)
//    seconds       -> cache-secs
//    prefetchBytes -> demuxer-readahead-secs is time-based in mpv;
//                     the byte figure is kept in the model for the
//                     segmented bookkeeping and reported in
//                     diagnostics, not forced onto an mpv option.
//    directory     -> cache-dir when set (file-backed cache);
//                     nil = memory only, no option emitted.
//  The back-buffer split (demuxer-max-back-bytes) is our own
//  choice: one third of capacity, the rest forward.
//

import Foundation

struct MPlayCachePolicy {
    /// Total cache capacity in bytes.
    var capacity: Int64
    /// Cache directory for file-backed caching; nil = memory only.
    var directory: String?
    /// Read-ahead target per stream, in bytes.
    var prefetchBytes: Int64
    /// Time-based cache target in seconds (mpv cache-secs).
    var seconds: Double
    /// Segment granularity in bytes.
    var segmentBytes: Int64
    /// Segment count; segments * segmentBytes == capacity in the
    /// standard policy.
    var segments: Int

    /// Our standard policy (values are OURS, not the original's):
    /// 96 segments x 4 MiB = 384 MiB capacity, 32 MiB prefetch,
    /// 120 s time target, memory only.
    static let standard = MPlayCachePolicy(
        capacity: 384 * 1024 * 1024,
        directory: nil,
        prefetchBytes: 32 * 1024 * 1024,
        seconds: 120,
        segmentBytes: 4 * 1024 * 1024,
        segments: 96
    )

    /// mpv option values derived from the policy (see header for the
    /// mapping and its approximations).
    var mpvOptions: [String: String] {
        var options: [String: String] = [
            "cache": "yes",
            "demuxer-max-bytes": "\(capacity)",
            "demuxer-max-back-bytes": "\(capacity / 3)",
            "cache-secs": String(format: "%.0f", seconds),
        ]
        if let directory {
            options["cache-dir"] = directory
        }
        return options
    }
}
