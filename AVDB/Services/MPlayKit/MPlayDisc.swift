//
//  MPlayDisc.swift
//  AVDB
//
//  Build 353 (full restoration): disc playback surface — the
//  original plays Blu-ray / DVD sources (its FFmpeg carries the
//  disc demuxers and its MediaInfo has a disc field).
//
//  Status, stated plainly: the API below is real and callable — a
//  dedicated player instance addressed as bd:// / dvd:// with the
//  device in the matching mpv option, chapters as the enumerable
//  title surface, mediaInfo() reporting the disc block.  The
//  NATIVE support is NOT in our libmpv build: mpv 0.41's meson
//  has libbluray / dvdnav feature options, but neither library is
//  in the pipeline's COMPONENTS (scripts/mplaykit59/
//  build_libmpv.py), so loadfile of a disc source fails inside
//  mpv and the failure surfaces through the open completion —
//  the session never pretends a disc opened.  Adding the two
//  libraries to the pipeline is the documented unblock path.
//

import Foundation

final class MPlayDiscSession {
    enum Kind {
        case bluRay, dvd

        var url: String { self == .bluRay ? "bd://" : "dvd://" }
        var deviceOption: String {
            self == .bluRay ? "bluray-device" : "dvd-device"
        }
        var infoKind: String { self == .bluRay ? "bluray" : "dvd" }
    }

    let kind: Kind
    let player: MPlayPlayer

    init(kind: Kind) throws {
        self.kind = kind
        self.player = try MPlayPlayer(options: ["cache": "no"])
    }

    /// Opens a disc device / image directory / ISO path.  The
    /// completion carries the real mpv result — with the current
    /// pipeline it fails (no libbluray/dvdnav), by design of the
    /// evidence trail, not silently.
    func open(devicePath: String,
              completion: @escaping (Result<Void, MPlayError>) -> Void) {
        player.setProp(kind.deviceOption, devicePath)
        player.open(url: kind.url, autoplay: false,
                    completion: completion)
    }

    /// The enumerable navigation surface stock mpv exposes for a
    /// loaded disc: its chapters.  (mpv has no title-list property
    /// for discs; the original's richer navigation comes from its
    /// own demuxer glue — documented gap.)
    func titles() -> [MPlayChapter] {
        player.chapters()
    }

    func mediaInfo() -> MPlayMediaInfo {
        player.mediaInfo()
    }

    func close() {
        player.close()
    }
}
