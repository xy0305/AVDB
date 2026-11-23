/*
 * MPlaySpatialBridge.c — rename-forward implementations for the
 * MPlayNative-style ABI declared in MPlaySpatialBridge.h.  Every
 * function forwards to the pinned upstream decoder C API
 * (LibTrueHD / LibDTSX, see UPSTREAM.md).  This layer exists so the
 * app links a stable mplay_ surface while the decoder libraries
 * stay swappable underneath — the same reason the original has it.
 */

#include "MPlaySpatialBridge.h"

/* ---- TrueHD / Atmos ---- */

uint32_t mplay_truehd_atmos_api_version(void)
{
    return truehd_atmos_api_version();
}

const char *mplay_truehd_atmos_version_string(void)
{
    return truehd_atmos_version_string();
}

const char *mplay_truehd_atmos_speaker_name(uint8_t speaker)
{
    return truehd_atmos_speaker_name(speaker);
}

TrueHDAtmosStatus mplay_truehd_atmos_selftest(void)
{
    return truehd_atmos_selftest();
}

TrueHDAtmosDecoder *mplay_truehd_atmos_decoder_create(int32_t presentation)
{
    return truehd_atmos_decoder_create(presentation);
}

void mplay_truehd_atmos_decoder_destroy(TrueHDAtmosDecoder *decoder)
{
    truehd_atmos_decoder_destroy(decoder);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_reset(TrueHDAtmosDecoder *decoder)
{
    return truehd_atmos_decoder_reset(decoder);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_set_presentation(TrueHDAtmosDecoder *decoder,
                                                              int32_t presentation)
{
    return truehd_atmos_decoder_set_presentation(decoder, presentation);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_push(TrueHDAtmosDecoder *decoder,
                                                  const uint8_t *data, size_t size,
                                                  int64_t pts)
{
    return truehd_atmos_decoder_push(decoder, data, size, pts);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_pull(TrueHDAtmosDecoder *decoder,
                                                  TrueHDAtmosBlock *block)
{
    return truehd_atmos_decoder_pull(decoder, block);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_get_stream_info(const TrueHDAtmosDecoder *decoder,
                                                             TrueHDAtmosStreamInfo *info)
{
    return truehd_atmos_decoder_get_stream_info(decoder, info);
}

TrueHDAtmosStatus mplay_truehd_atmos_decoder_get_stats(const TrueHDAtmosDecoder *decoder,
                                                       TrueHDAtmosStats *stats)
{
    return truehd_atmos_decoder_get_stats(decoder, stats);
}

const char *mplay_truehd_atmos_decoder_last_error(const TrueHDAtmosDecoder *decoder)
{
    return truehd_atmos_decoder_last_error(decoder);
}

/* ---- DTS:X ---- */

uint32_t mplay_dtsx_api_version(void)
{
    return dtsx_api_version();
}

const char *mplay_dtsx_version_string(void)
{
    return dtsx_version_string();
}

const char *mplay_dtsx_speaker_name(uint8_t speaker)
{
    return dtsx_speaker_name(speaker);
}

const char *mplay_dtsx_presentation_name(uint32_t presentation)
{
    return dtsx_presentation_name(presentation);
}

DTSXStatus mplay_dtsx_selftest(void)
{
    return dtsx_selftest();
}

DTSXDecoder *mplay_dtsx_decoder_create(void)
{
    return dtsx_decoder_create();
}

void mplay_dtsx_decoder_destroy(DTSXDecoder *decoder)
{
    dtsx_decoder_destroy(decoder);
}

DTSXStatus mplay_dtsx_decoder_reset(DTSXDecoder *decoder)
{
    return dtsx_decoder_reset(decoder);
}

DTSXStatus mplay_dtsx_decoder_push(DTSXDecoder *decoder, const uint8_t *data,
                                   size_t size, int64_t pts)
{
    return dtsx_decoder_push(decoder, data, size, pts);
}

DTSXStatus mplay_dtsx_decoder_pull(DTSXDecoder *decoder, DTSXBlock *block)
{
    return dtsx_decoder_pull(decoder, block);
}

DTSXStatus mplay_dtsx_decoder_get_stream_info(const DTSXDecoder *decoder,
                                              DTSXStreamInfo *info)
{
    return dtsx_decoder_get_stream_info(decoder, info);
}

DTSXStatus mplay_dtsx_decoder_get_stats(const DTSXDecoder *decoder, DTSXStats *stats)
{
    return dtsx_decoder_get_stats(decoder, stats);
}

const char *mplay_dtsx_decoder_last_error(const DTSXDecoder *decoder)
{
    return dtsx_decoder_last_error(decoder);
}

/* ---- Combined ---- */

int mplay_spatial_unwind_selftest(void)
{
    if (truehd_atmos_selftest() != TRUEHD_ATMOS_OK)
        return 1;
    if (dtsx_selftest() != DTSX_OK)
        return 2;
    return 0;
}
