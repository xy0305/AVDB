# Build 284: DMM covers for 800 px jacket-only titles (IPX-706)

## Symptom

On build 283 the IPX-706 detail page showed **封面来源：JavDB**, even though DMM has the cover.

## Root cause (reproduced, not a network problem)

- **What DMM actually has for IPX-706** (measured from the box, 2026-10-29):
  - `ipx00706ps.jpg` is only a **147×200** thumbnail, on both awsimgsrc and pics. Mono `ipx706ps.jpg` is the same.
  - `ipx00706pl.jpg` is an **800×538** jacket. awsimgsrc, pics, and both mono copies are identical.
  - `?w=1600` returns 1600×1076, but its high-frequency energy matches a bicubic upscale of the 800 px file (1612 vs 1651). DMM has no higher-resolution original.
- **JavDB's cover** (`c0.jdbstatic.com/covers/pr/pRX45.jpg`) is the same 800×538 jacket, re-hosted.
- **The 282 resolver behaved correctly:**
  - Candidates were `ipx00706` ps and pl, admitted.
  - The ps was correctly rejected as a 147×200 placeholder-size image.
  - The pl was downloaded and front-cropped to **371×538** (0.69·h).
- **Why JavDB still won:** JavDB's copy of the same jacket is cropped at 0.70·h to **376×538**. `DetailPosterQuality.winner` picks the highest score, so JavDB won by 1.3%.
- **How common this is:** in the 510-title sample, 67 DMM hits (13%) are jacket-only 800×5xx titles like this, mostly older IPX / SSIS-era releases. All of them lost the same way.
- **Ruled out:**
  - No DNS pre-flight runs on cover requests, so the Loon / fake-ip changes don't matter here.
  - No redirects: awsimgsrc returns 200 directly.
  - Caching is in-memory, with a 120 s positive TTL.

## Fix

1. **Official source wins near-ties.** Among derived fronts within 5% of the best score, publisher or store originals win: DMM, MGS, Amazon and Tenhow rank above other hosts, which rank above JavDB. An original portrait still beats any crop, and a JavDB raster more than 5% larger still wins.
2. **DMM candidates come right after the first JavDB anchor**, so a second JavDB size or metadata copy can't push the DMM jacket out of the four non-discovery slots.
3. **Same-image alternates inside one slot.** If an awsimgsrc digital URL fails (HTTP error, timeout, proxy or region refusal, placeholder), the same slot tries, in order:
   - pics digital
   - awsimgsrc mono (`ipx706`)
   - pics mono `adult/`

   The CID namespace and serial are always kept, so it is never a different title.
4. **Stale fallbacks re-resolve.** A JavDB winner is cached for only 20 s, so a later DMM success replaces it on the next open. The detail cache key also carries `dmm284`, so old results are not reused.
5. **List cards and history:** they try the DMM ps and then the DMM pl (front-cropped by `loadPoster`), and JavDB is always kept as the third of the three list attempts.

## Result

- **IPX-706:** the DMM 800×538 jacket, front-cropped to 371×538, wins → **封面来源：DMM**. This is the highest-resolution cover any public source has for this title; the IdeaPocket site jacket is 360×504.
- **Hit rate:** the 282 measurement was rerun with a fresh probe cache:
  - DMM HQ available: N = 510, before 322 (63.1%) → **481 (94.3%)**, of which 414 are full-portrait ps.
  - Same misses as before (MGS-only or not on DMM).
- **Effective DMM shown** (estimate): 283 ≈ 414 (81.2%) → 284 ≈ 481 (94.3%). This assumes JavDB's copy of each 800 px jacket is the same size, which was verified for IPX-706.

## Tests

`scripts/test-dmm-covers284.py` checks, for IPX-706:

- candidates and the mono CID
- the alternates chain
- 147×200 ps rejected, 800×538 pl kept as a jacket, and the crop
- the reproduced tie, with DMM now winning, independent of input order
- a bigger JavDB raster and the MILK-311 portrait both unchanged
- official sources preferred over others
- the JavDB-fallback TTL re-resolving to DMM
- the list three-slot guarantee
- version 284
