//
//  MPlayStreamBridge.c
//  AVDB
//
//  See MPlayStreamBridge.h.  A small fixed registry maps schemes to
//  Swift hook tables; the mpv open callback trampolines through it.
//  Per libmpv's contract the callbacks never call back into libmpv
//  on the same handle.
//

#include "MPlayStreamBridge.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

// mpv/stream_cb.h (0.41) replica — layout verified against the
// pinned headers; do not edit without re-checking them.
typedef int64_t (*mplay_cb_read_fn)(void *cookie, char *buf, uint64_t size);
typedef int64_t (*mplay_cb_seek_fn)(void *cookie, int64_t offset);
typedef int64_t (*mplay_cb_size_fn)(void *cookie);
typedef void (*mplay_cb_close_fn)(void *cookie);
typedef void (*mplay_cb_cancel_fn)(void *cookie);
typedef struct mplay_stream_cb_info {
    void *cookie;
    mplay_cb_read_fn read_fn;
    mplay_cb_seek_fn seek_fn;
    mplay_cb_size_fn size_fn;
    mplay_cb_close_fn close_fn;
    mplay_cb_cancel_fn cancel_fn;
} mplay_stream_cb_info;
_Static_assert(sizeof(mplay_stream_cb_info) == 6 * sizeof(void *),
               "mpv_stream_cb_info layout drifted from mpv 0.41");

typedef int (*mplay_cb_open_fn)(void *user_data, const char *uri,
                                mplay_stream_cb_info *info);
extern int mpv_stream_cb_add_ro(void *ctx, const char *protocol,
                                void *user_data, mplay_cb_open_fn open_fn);

#define MPLAY_STREAM_MAX_SCHEMES 16
#define MPLAY_STREAM_SCHEME_MAX 32

typedef struct MPlayStreamEntry {
    char scheme[MPLAY_STREAM_SCHEME_MAX];
    MPlayStreamHooks hooks;
    int used;
} MPlayStreamEntry;

static MPlayStreamEntry mplay_stream_registry[MPLAY_STREAM_MAX_SCHEMES];
static pthread_mutex_t mplay_stream_lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct MPlayStreamInstance {
    MPlayStreamHooks hooks;
    void *cookie;
} MPlayStreamInstance;

static int64_t mplay_cb_read(void *cookie, char *buf, uint64_t size) {
    MPlayStreamInstance *stream = (MPlayStreamInstance *)cookie;
    if (!stream || !stream->hooks.read) return -19; // MPV_ERROR_GENERIC
    return stream->hooks.read(stream->cookie, buf, size);
}

static int64_t mplay_cb_seek(void *cookie, int64_t offset) {
    MPlayStreamInstance *stream = (MPlayStreamInstance *)cookie;
    if (!stream || !stream->hooks.seek) return -17; // UNSUPPORTED
    return stream->hooks.seek(stream->cookie, offset);
}

static int64_t mplay_cb_size(void *cookie) {
    MPlayStreamInstance *stream = (MPlayStreamInstance *)cookie;
    if (!stream || !stream->hooks.size) return -17; // UNSUPPORTED
    return stream->hooks.size(stream->cookie);
}

static void mplay_cb_close(void *cookie) {
    MPlayStreamInstance *stream = (MPlayStreamInstance *)cookie;
    if (!stream) return;
    if (stream->hooks.close) stream->hooks.close(stream->cookie);
    free(stream);
}

static void mplay_cb_cancel(void *cookie) {
    MPlayStreamInstance *stream = (MPlayStreamInstance *)cookie;
    if (stream && stream->hooks.cancel) stream->hooks.cancel(stream->cookie);
}

static int mplay_cb_open(void *user_data, const char *uri,
                         mplay_stream_cb_info *info) {
    MPlayStreamEntry *entry = (MPlayStreamEntry *)user_data;
    if (!entry || !entry->hooks.open || !entry->hooks.read || !info)
        return -12; // MPV_ERROR_LOADING_FAILED
    void *cookie = NULL;
    if (entry->hooks.open(entry->hooks.context, uri, &cookie) != 0 ||
        cookie == NULL)
        return -12;
    MPlayStreamInstance *stream =
        (MPlayStreamInstance *)calloc(1, sizeof(MPlayStreamInstance));
    if (!stream) {
        if (entry->hooks.close) entry->hooks.close(cookie);
        return -12;
    }
    stream->hooks = entry->hooks;
    stream->cookie = cookie;
    info->cookie = stream;
    info->read_fn = mplay_cb_read;
    info->seek_fn = entry->hooks.seek ? mplay_cb_seek : NULL;
    info->size_fn = entry->hooks.size ? mplay_cb_size : NULL;
    info->close_fn = mplay_cb_close;
    info->cancel_fn = entry->hooks.cancel ? mplay_cb_cancel : NULL;
    return 0;
}

MPlayStreamHooks mplay_stream_hooks_make(
    void *context,
    MPlayStreamOpenFn open_fn,
    MPlayStreamReadFn read_fn,
    MPlayStreamSeekFn seek_fn,
    MPlayStreamSizeFn size_fn,
    MPlayStreamCloseFn close_fn,
    MPlayStreamCancelFn cancel_fn) {
    MPlayStreamHooks hooks;
    hooks.context = context;
    hooks.open = open_fn;
    hooks.read = read_fn;
    hooks.seek = seek_fn;
    hooks.size = size_fn;
    hooks.close = close_fn;
    hooks.cancel = cancel_fn;
    return hooks;
}

int mplay_stream_register(void *mpv_handle, const char *scheme,
                          MPlayStreamHooks hooks) {
    if (!mpv_handle || !scheme || !hooks.open || !hooks.read || !hooks.close)
        return -2; // MPV_ERROR_INVALID_PARAMETER
    size_t length = strlen(scheme);
    if (length == 0 || length >= MPLAY_STREAM_SCHEME_MAX) return -2;
    pthread_mutex_lock(&mplay_stream_lock);
    MPlayStreamEntry *slot = NULL;
    for (int i = 0; i < MPLAY_STREAM_MAX_SCHEMES; i++) {
        if (mplay_stream_registry[i].used &&
            strcmp(mplay_stream_registry[i].scheme, scheme) == 0) {
            slot = &mplay_stream_registry[i]; // re-register: replace hooks
            break;
        }
        if (!mplay_stream_registry[i].used && !slot)
            slot = &mplay_stream_registry[i];
    }
    if (!slot) {
        pthread_mutex_unlock(&mplay_stream_lock);
        return -1;
    }
    memcpy(slot->scheme, scheme, length + 1);
    slot->hooks = hooks;
    slot->used = 1;
    pthread_mutex_unlock(&mplay_stream_lock);
    return mpv_stream_cb_add_ro(mpv_handle, scheme, slot, mplay_cb_open);
}
