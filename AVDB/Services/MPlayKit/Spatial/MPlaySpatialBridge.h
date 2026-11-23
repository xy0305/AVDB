/*
 * MPlaySpatialBridge.h — MPlayNative-style ABI for spatial audio.
 *
 * Build 353 full restoration, stage D.  This is OUR bridge layer in
 * the shape of the original's MPlayNative ABI (IOS-FINDINGS §2.4:
 * the original's main binary links a mplay_-prefixed set that wraps
 * the object-audio decoders; the per-decoder callbacks are
 * registered behind it, rendering constrained to 48 kHz).
 *
 * Every function here is a rename-forward to the pinned upstream
 * C API declared in the vendored headers next to this file
 * (truehd_atmos.h — LibTrueHD @ 3eab2e7c, MIT wrapper + Apache-2.0
 * decoder; dtsx.h — LibDTSX @ 6f0b321e, Apache-2.0 wrapper with an
 * LGPL-2.1-or-later FFmpeg-derived decoder; see UPSTREAM.md).
 * Types are the upstream types; nothing is redefined.
 */

#ifndef MPLAY_SPATIAL_BRIDGE_H
#define MPLAY_SPATIAL_BRIDGE_H

#include "truehd_atmos.h"
#include "dtsx.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- TrueHD / Atmos (forwards to truehd_atmos_*) ---- */

uint32_t mplay_truehd_atmos_api_version(void);
const char *mplay_truehd_atmos_version_string(void);
const char *mplay_truehd_atmos_speaker_name(uint8_t speaker);
TrueHDAtmosStatus mplay_truehd_atmos_selftest(void);
TrueHDAtmosDecoder *mplay_truehd_atmos_decoder_create(int32_t presentation);
void mplay_truehd_atmos_decoder_destroy(TrueHDAtmosDecoder *decoder);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_reset(TrueHDAtmosDecoder *decoder);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_set_presentation(TrueHDAtmosDecoder *decoder,
                                                              int32_t presentation);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_push(TrueHDAtmosDecoder *decoder,
                                                  const uint8_t *data, size_t size,
                                                  int64_t pts);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_pull(TrueHDAtmosDecoder *decoder,
                                                  TrueHDAtmosBlock *block);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_get_stream_info(const TrueHDAtmosDecoder *decoder,
                                                             TrueHDAtmosStreamInfo *info);
TrueHDAtmosStatus mplay_truehd_atmos_decoder_get_stats(const TrueHDAtmosDecoder *decoder,
                                                       TrueHDAtmosStats *stats);
const char *mplay_truehd_atmos_decoder_last_error(const TrueHDAtmosDecoder *decoder);

/* ---- DTS:X (forwards to dtsx_*) ---- */

uint32_t mplay_dtsx_api_version(void);
const char *mplay_dtsx_version_string(void);
const char *mplay_dtsx_speaker_name(uint8_t speaker);
const char *mplay_dtsx_presentation_name(uint32_t presentation);
DTSXStatus mplay_dtsx_selftest(void);
DTSXDecoder *mplay_dtsx_decoder_create(void);
void mplay_dtsx_decoder_destroy(DTSXDecoder *decoder);
DTSXStatus mplay_dtsx_decoder_reset(DTSXDecoder *decoder);
DTSXStatus mplay_dtsx_decoder_push(DTSXDecoder *decoder, const uint8_t *data,
                                   size_t size, int64_t pts);
DTSXStatus mplay_dtsx_decoder_pull(DTSXDecoder *decoder, DTSXBlock *block);
DTSXStatus mplay_dtsx_decoder_get_stream_info(const DTSXDecoder *decoder,
                                              DTSXStreamInfo *info);
DTSXStatus mplay_dtsx_decoder_get_stats(const DTSXDecoder *decoder, DTSXStats *stats);
const char *mplay_dtsx_decoder_last_error(const DTSXDecoder *decoder);

/* ---- Combined ---- */

/** Runs both decoders' unwind selftests (the original's
 *  mplay_spatial_unwind_selftest).  Returns 0 when both pass. */
int mplay_spatial_unwind_selftest(void);

#ifdef __cplusplus
}
#endif

#endif /* MPLAY_SPATIAL_BRIDGE_H */
