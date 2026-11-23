//
//  MPlayStreamBridge.h
//  AVDB
//
//  Build 353 (full restoration): C glue for custom stream protocols —
//  the equivalent of the original's registerStreamProtocol(scheme:
//  factory:).  mpv's stream callback API (mpv/stream_cb.h, 0.41) is
//  bridged to Swift factories through the hook table below so Swift
//  never has to fill a libmpv struct itself.
//
//  The mpv_stream_cb_info layout replicated here is the one from the
//  pinned mpv 0.41 headers (verified against include/mpv/stream_cb.h:
//  cookie, read_fn, seek_fn, size_fn, close_fn, cancel_fn); a static
//  assert pins its size.  mpv_stream_cb_add_ro is declared locally so
//  this file does not depend on the Libmpv framework header layout.
//

#ifndef MPLAY_STREAM_BRIDGE_H
#define MPLAY_STREAM_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Swift-side factory hooks.  `context` is an opaque retained pointer
/// owned by the registering MPlayPlayer; the per-stream `cookie`
/// values are produced by `open` and handed back to every other hook.
/// Return conventions mirror mpv's: read returns bytes read (0 = EOF,
/// negative = error), seek/size return the new offset / total size or
/// a negative mpv error (MPV_ERROR_UNSUPPORTED = -17 when the reader
/// cannot provide the operation — in that case leave the hook NULL).
typedef int     (*MPlayStreamOpenFn)(void *context, const char *uri,
                                     void **cookie_out);
typedef int64_t (*MPlayStreamReadFn)(void *cookie, char *buffer,
                                     uint64_t size);
typedef int64_t (*MPlayStreamSeekFn)(void *cookie, int64_t offset);
typedef int64_t (*MPlayStreamSizeFn)(void *cookie);
typedef void    (*MPlayStreamCloseFn)(void *cookie);
typedef void    (*MPlayStreamCancelFn)(void *cookie);

typedef struct MPlayStreamHooks {
    void *context;
    MPlayStreamOpenFn open;
    MPlayStreamReadFn read;
    MPlayStreamSeekFn seek;    // may be NULL
    MPlayStreamSizeFn size;    // may be NULL
    MPlayStreamCloseFn close;
    MPlayStreamCancelFn cancel; // may be NULL
} MPlayStreamHooks;

/// Builds a hooks struct from parts (Swift fills structs with
/// function pointers awkwardly; calling one C function with closures
/// is the proven pattern in this codebase).
MPlayStreamHooks mplay_stream_hooks_make(
    void *context,
    MPlayStreamOpenFn open_fn,
    MPlayStreamReadFn read_fn,
    MPlayStreamSeekFn seek_fn,
    MPlayStreamSizeFn size_fn,
    MPlayStreamCloseFn close_fn,
    MPlayStreamCancelFn cancel_fn);

/// Registers `scheme` on the given mpv core (an mpv_handle passed as
/// void*).  Returns 0 on success, MPV_ERROR_INVALID_PARAMETER (-2)
/// for bad input, or -1 when the registry is full.  Registrations
/// live until the core is destroyed (libmpv has no unregister).
int mplay_stream_register(void *mpv_handle, const char *scheme,
                          MPlayStreamHooks hooks);

#ifdef __cplusplus
}
#endif

#endif /* MPLAY_STREAM_BRIDGE_H */
