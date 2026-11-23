//
//  MPlayAudioPolicy.swift
//  AVDB
//
//  Build 353 (full restoration): the audio-route policy types from
//  the original's findings — EAC3PassthroughDecision (the two
//  symbol-verified fields) and the AudioRouteOutputOverride
//  surface — plus the relay tuning setters' home documentation.
//
//  How the policy is consumed here: AVDB's own audio path is
//  mpv's audiounit ao (the original's build enables audiounit too);
//  bitstream passthrough is not something stock mpv's iOS ao
//  offers, so `shouldPassthrough` evaluates the decision for the
//  SPATIAL route: when the decision says passthrough and the route
//  cannot carry the bitstream, the object-audio decode path
//  (MPlaySpatial) is the fallback — which is exactly the fork the
//  original's decision type exists to make.  The decision logic is
//  real; the passthrough output itself has no iOS landing in our
//  stack and is documented as such.
//

import Foundation

/// The original's EAC3PassthroughDecision (fields per symbols).
struct EAC3PassthroughDecision {
    var trackCodec: String = ""
    var trackHasEAC3: Bool = false

    /// Passthrough is chosen only for an E-AC-3 (or AC-3-family)
    /// track on a route that can carry the bitstream.
    func shouldPassthrough(routeSupportsPassthrough: Bool) -> Bool {
        guard routeSupportsPassthrough else { return false }
        if trackHasEAC3 { return true }
        let codec = trackCodec.lowercased()
        return codec.contains("eac3") || codec.contains("ac3")
    }

    /// Builds a decision from a live player's selected audio track.
    static func current(in player: MPlayPlayer) -> EAC3PassthroughDecision {
        var decision = EAC3PassthroughDecision()
        if let track = player.trackSnapshot().first(
            where: { $0.kind == "audio" && $0.selected }) {
            decision.trackCodec = track.codec
            let codec = track.codec.lowercased()
            decision.trackHasEAC3 = codec.contains("eac3")
        }
        return decision
    }
}

/// The original's audio-route override surface.
enum AudioRouteOutputOverride: String {
    /// Follow the passthrough decision + route capabilities.
    case automatic
    /// Force multichannel PCM (the spatial renderer's PCM route).
    case pcm
    /// Force the APAC/HLS system-spatial route when available.
    case systemSpatial
    /// Force bitstream passthrough (no iOS landing in our stack —
    /// selecting it falls back to PCM and logs; see header).
    case passthrough
}

/// Applies an override to a relay: returns the route the relay
/// will actually take, so callers never mistake the request for
/// the outcome.
func mplayApplyAudioRouteOverride(
    _ override: AudioRouteOutputOverride,
    decision: EAC3PassthroughDecision,
    relay: MPlayAudioRelay
) -> MPlayAudioRelay.Route {
    switch override {
    case .automatic, .systemSpatial:
        return relay.route
    case .pcm:
        return .pcmFallback
    case .passthrough:
        if decision.shouldPassthrough(routeSupportsPassthrough: false) {
            return relay.route
        }
        MPlayDiagnostics.log(
            "audio route: passthrough requested but unavailable on iOS stack; PCM fallback")
        return .pcmFallback
    }
}
