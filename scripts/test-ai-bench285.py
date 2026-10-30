#!/usr/bin/env python3
"""Build 285 (macOS CI): compile the bundled Core ML model and run the shipping tiled SR engine on
neutral fixtures — timings per compute-unit set, fp16 parity vs PyTorch fp32, compute plan."""
import platform, subprocess, sys, tempfile, json
from pathlib import Path
r = Path(__file__).resolve().parents[1]; out = r / 'evidence-ai285'; out.mkdir(exist_ok=True)
assert platform.system() == 'Darwin'
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    subprocess.run(['xcrun', 'coremlcompiler', 'compile', str(r / 'AVDB/Resources/CoverSR.mlpackage'), str(td)], check=True)
    exe = td / 'bench'
    (td / 'main.swift').write_text((r / 'scripts/AICoverBench285.swift').read_text())
    subprocess.run(['xcrun', 'swiftc', '-O', '-target', 'arm64-apple-macos14.4', '-o', str(exe),
                    str(r / 'AVDB/Services/AICoverPolicy.swift'), str(r / 'AVDB/Services/AICoverSREngine.swift'), str(td / 'main.swift')], check=True)
    code = subprocess.call([str(exe), str(td / 'CoverSR.mlmodelc'), str(r / 'scripts/fixtures285'), str(out)])
    subprocess.run(['du', '-sh', str(td / 'CoverSR.mlmodelc')], check=False)
sys.exit(code)
