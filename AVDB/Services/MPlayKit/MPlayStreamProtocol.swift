//
//  MPlayStreamProtocol.swift
//  AVDB
//
//  Build 353 (full restoration): custom stream protocols — the
//  equivalent of the original Player's registerStreamProtocol(
//  scheme:factory:).  A host registers a factory for a URL scheme;
//  mpv then opens "scheme://…" URLs through the factory's readers
//  via the C bridge (MPlayStreamBridge) and mpv_stream_cb_add_ro.
//
//  Known shape differences from the original, stated plainly:
//   * Registrations are per-core in libmpv, but the bridge registry
//     is process-global: registering the same scheme from two cores
//     replaces the first core's hooks.  the host runs one playback core
//     at a time (plus short-lived preload instances), so schemes are
//     effectively app-global here.
//   * libmpv has no unregister; a registration lives until the core
//     is destroyed.  The factory box is released when the player
//     closes (after mpv_terminate_destroy, when callbacks can no
//     longer fire).
//

import Foundation

/// One opened custom stream.  Implementations must tolerate `read`
/// being called from mpv's demuxer threads and `cancel` from yet
/// another thread while a read is blocked.
protocol MPlayStreamReader: AnyObject {
    /// Fill `buffer`; return bytes read (>0), 0 at EOF, negative on
    /// error.  Called with the buffer's full capacity each time.
    func mplayRead(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int
    /// Seek to an absolute offset; return the new offset, or a
    /// negative mpv error (-17 = unsupported).  Optional.
    func mplaySeek(to offset: Int64) -> Int64
    /// Total stream size, or a negative mpv error.  Optional.
    var mplaySize: Int64 { get }
    /// The stream is being abandoned (e.g. during a seek storm);
    /// unblock any pending read.  Optional.
    func mplayCancel()
}

extension MPlayStreamReader {
    func mplaySeek(to offset: Int64) -> Int64 { -17 }
    var mplaySize: Int64 { -17 }
    func mplayCancel() {}
}

/// Retains the factory for the C bridge.  One box per registration;
/// the player owns the retain and releases it in close().  Internal
/// (not private) because MPlayPlayer.closeOnQueue balances the
/// retain by concrete type.
final class MPlayStreamFactoryBox {
    let factory: (String) throws -> MPlayStreamReader
    init(factory: @escaping (String) throws -> MPlayStreamReader) {
        self.factory = factory
    }
}

// MARK: - C callbacks (file-scope: @convention(c) cannot capture)

private func mplayStreamOpenCB(
    context: UnsafeMutableRawPointer?,
    uri: UnsafePointer<CChar>?,
    cookieOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32 {
    guard let context, let uri, let cookieOut else { return -1 }
    let box = Unmanaged<MPlayStreamFactoryBox>
        .fromOpaque(context).takeUnretainedValue()
    do {
        let reader = try box.factory(String(cString: uri))
        cookieOut.pointee = Unmanaged.passRetained(reader as AnyObject)
            .toOpaque()
        return 0
    } catch {
        MPlayDiagnostics.log("stream: factory failed: \(error)")
        return -1
    }
}

private func mplayStreamReadCB(
    cookie: UnsafeMutableRawPointer?,
    buffer: UnsafeMutablePointer<CChar>?,
    size: UInt64
) -> Int64 {
    guard let cookie, let buffer, size > 0 else { return -1 }
    let reader = Unmanaged<AnyObject>.fromOpaque(cookie)
        .takeUnretainedValue() as! MPlayStreamReader
    let bytes = UnsafeMutableBufferPointer(
        start: UnsafeMutableRawPointer(buffer)
            .assumingMemoryBound(to: UInt8.self),
        count: Int(min(size, UInt64(Int.max)))
    )
    return Int64(reader.mplayRead(into: bytes))
}

private func mplayStreamSeekCB(
    cookie: UnsafeMutableRawPointer?, offset: Int64
) -> Int64 {
    guard let cookie else { return -17 }
    let reader = Unmanaged<AnyObject>.fromOpaque(cookie)
        .takeUnretainedValue() as! MPlayStreamReader
    return reader.mplaySeek(to: offset)
}

private func mplayStreamSizeCB(cookie: UnsafeMutableRawPointer?) -> Int64 {
    guard let cookie else { return -17 }
    let reader = Unmanaged<AnyObject>.fromOpaque(cookie)
        .takeUnretainedValue() as! MPlayStreamReader
    return reader.mplaySize
}

private func mplayStreamCloseCB(cookie: UnsafeMutableRawPointer?) {
    guard let cookie else { return }
    // Balances the passRetained in the open callback.
    Unmanaged<AnyObject>.fromOpaque(cookie).release()
}

private func mplayStreamCancelCB(cookie: UnsafeMutableRawPointer?) {
    guard let cookie else { return }
    let reader = Unmanaged<AnyObject>.fromOpaque(cookie)
        .takeUnretainedValue() as! MPlayStreamReader
    reader.mplayCancel()
}

extension MPlayPlayer {
    /// Registers a custom stream protocol on this core (see the file
    /// header for the global-registry caveat).  Returns the bridge /
    /// libmpv result code (0 = success).  The factory is retained
    /// until close().
    @discardableResult
    func registerStreamProtocol(
        scheme: String,
        factory: @escaping (String) throws -> MPlayStreamReader
    ) -> Int32 {
        let box = MPlayStreamFactoryBox(factory: factory)
        let context = Unmanaged.passRetained(box).toOpaque()
        var registered = false
        defer { if !registered { Unmanaged<MPlayStreamFactoryBox>.fromOpaque(context).release() } }
        var rc: Int32 = -2
        _ = withCore { core in
            let hooks = mplay_stream_hooks_make(
                context,
                mplayStreamOpenCB,
                mplayStreamReadCB,
                mplayStreamSeekCB,
                mplayStreamSizeCB,
                mplayStreamCloseCB,
                mplayStreamCancelCB
            )
            rc = scheme.withCString { cScheme in
                mplay_stream_register(UnsafeMutableRawPointer(core), cScheme, hooks)
            }
        }
        guard rc == 0 else { return rc }
        registered = true
        retainStreamContext(context)
        return 0
    }
}
