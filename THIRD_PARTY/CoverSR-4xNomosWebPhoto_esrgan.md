# CoverSR.mlpackage (Build 285 AI 封面画质增强)

- Model: **4xNomosWebPhoto_esrgan** by Philip Hofmann (Phhofm)
  https://github.com/Phhofm/models/releases/tag/4xNomosWebPhoto_esrgan (released 2024-06-16)
  - Release notes state "License: CC-BY-0.4" (read as Creative Commons Attribution 4.0, CC BY 4.0;
    attribution given here). 4× ESRGAN (RRDBNet, 16.7 M params) for photography, trained on
    Nomos-v2 with realistic noise, lens blur and JPEG / WebP re-compression; fine-tuned from
    RealESRGAN_x4plus.
- Architecture: ESRGAN / Real-ESRGAN, © Xintao Wang et al., BSD-3-Clause
  (https://github.com/xinntao/Real-ESRGAN).
- Conversion (unchanged weights): PyTorch → Core ML ML Program with coremltools 9.0,
  fp16 compute + fp16 I/O, static input 1×3×128×128 → output 1×3×512×512 (tiled in-app with
  12 px overlap and linear feathering), minimum deployment iOS 17. Output is clamped to 0…1.
