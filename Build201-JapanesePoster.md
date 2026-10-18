# Build 201 — Japanese detail poster discovery

Base: c175242d126e46fb0dc3cc7a1b7b5e493d762295 (build 200).

## Evidence and scope

The reported record is MmemxP / SSIS-794 / 2023-07-12. A fresh official API query through the system-trusted browser TLS stack returned numeric type 0, which Movie decodes as string "0"; the known female actor identity maps to /kiyohara_miyuu.html. It is not a Western/original classification. The screenshot's displayed JavDB source is 800×438. That raster fails the established portrait policy (and its 1.826 aspect ratio is outside the supported DVD wrap crop range); even a hypothetical 306×438 front would fail 360×500. It must not be upsampled or declared a poster winner.

Normal verified TLS requests found the exact Tenhow record linking retail CID ssis794, digital CID ssis00794 and ASIN B0C7TQ7DJR. Its image decoded to 1055×1500. All four tested exact DMM ps variants decoded to 147×200 and are correctly rejected. Japanese Amazon returned HTTP 500; no captcha bypass or fabricated Amazon image URL was used. This proves one high-quality source was reachable during this investigation, not that every visit/network or every SSIS title has a winner.

The 197→200 comparison leaves the Japanese classification, geometry thresholds, Tenhow parser, actor map, scheduler and discovery deadline unchanged. Build 200's fallback source callback only records provenance; it does not assign poster layout. Therefore the screenshot alone does not prove a build-200 Japanese algorithm regression. An unavailable/rejected candidate outcome already selected the legacy fallback in build 197.

## Actual defect fixed

A trusted navigation seed was retained forever by `posterSeed ?? vm.movie`. A seed can pass navigationSeed with nonempty actor identities yet have no mapped discovery path. A later full detail response can supply the exact actor, but could never enable Tenhow discovery. The resolver now upgrades only such a missing-path seed when the matching detail ID supplies a valid path. Complete seeds keep the same cache identity and remain immune to unrelated metadata refreshes. Unknown seeds still cannot start an original-category negative result before detail metadata.

This is a verified sparse-metadata defect shared with the earlier baseline; it is not presented as conclusive causation of the supplied user's visit.

## Diagnostics and invariants

The existing source/pixel line remains tied to the displayed bitmap. A small secondary caption on non-Western fallback identifies original-preservation, unsupported source, no qualifying candidate (network or pixels), or actual exhaustion of the 12-second selection budget. It does not claim to distinguish every transport error from every rejected image. Western TPDB preferences, source enrichment and dedicated invalidation are retained. No quality threshold, crop geometry, FC2/uncensored original handling, six-image/two-concurrent/twelve-second budget or single-publication contract is relaxed. No subtitle test is removed.

## Regression coverage

Neutral ImageIO fixtures assert numeric type 0 for SSIS-794; sparse seed → exact actor detail discovery; complete seed identity stability; unknown seed rejection; true 800×438 rejection; 306×438 rejection; 1055×1500 eligibility/provenance; exact retail/digital CID → ASIN match; and uncensored/FC2 exclusion. Existing Western, cache, EXIF, concurrency and UI contracts remain enabled. Dedicated macOS simulator coverage is in Japanese poster 201 regressions, with iPhone and iPad matrices. Release compilation and IPA packaging remain in the existing build workflow.
