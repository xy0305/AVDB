#!/usr/bin/env python3
"""Reproduce AVDB/Resources/CoverSR.mlpackage (Build 285).
pip install torch==2.7.0 coremltools==9.0 spandrel==0.4.2 ; download
https://github.com/Phhofm/models/releases/download/4xNomosWebPhoto_esrgan/4xNomosWebPhoto_esrgan.pth"""
import sys, numpy as np, torch, coremltools as ct, spandrel
pth, out, tile = sys.argv[1], sys.argv[2], 128
d = spandrel.ModelLoader().load_from_file(pth)
class Wrap(torch.nn.Module):
    def __init__(s, n): super().__init__(); s.n = n
    def forward(s, x): return s.n(x).clamp(0, 1)
w = Wrap(d.model.eval().float()).eval()
with torch.no_grad(): tr = torch.jit.trace(w, torch.rand(1, 3, tile, tile))
ml = ct.convert(tr, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS17,
    inputs=[ct.TensorType(name='input', shape=(1, 3, tile, tile), dtype=np.float16)],
    outputs=[ct.TensorType(name='output', dtype=np.float16)],
    compute_precision=ct.precision.FLOAT16, compute_units=ct.ComputeUnit.ALL)
ml.short_description = f'4xNomosWebPhoto_esrgan x{d.scale} super-resolution, tile {tile}'
ml.user_defined_metadata.update({'scale': str(d.scale), 'tile': str(tile), 'source': '4xNomosWebPhoto_esrgan'})
ml.save(out)
