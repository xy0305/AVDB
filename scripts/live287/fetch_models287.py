#!/usr/bin/env python3
"""Build 287: populate AVDB/Resources/LiveModels (bundled into the IPA; not committed to git).

  openai_whisper-large-v3-v20240930_turbo_632MB/   argmaxinc/whisperkit-coreml (MIT)   default tier
  openai_whisper-small_216MB/                      argmaxinc/whisperkit-coreml (MIT)   thermal / battery degrade tier
  tokenizer-large-v3/, tokenizer-small/            openai/whisper-large-v3, openai/whisper-small (MIT)
  nllb/NLLBEncoder.mlmodelc, NLLBDecoder.mlmodelc  facebook/nllb-200-distilled-600M (CC-BY-NC-4.0), converted here
Usage: fetch_models287.py OUT_DIR [--skip-nllb]"""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
from huggingface_hub import snapshot_download

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
WK_REPO, WK_REV = "argmaxinc/whisperkit-coreml", "main"
TIERS = {"openai_whisper-large-v3-v20240930_turbo_632MB": "openai/whisper-large-v3", "openai_whisper-small_216MB": "openai/whisper-small"}
TOK = {"openai/whisper-large-v3": "tokenizer-large-v3", "openai/whisper-small": "tokenizer-small"}
log = {}
t0 = time.time()
snap = snapshot_download(WK_REPO, revision=WK_REV, allow_patterns=[f"{k}/*" for k in TIERS])
for k in TIERS:
    dst = out / k
    if dst.exists(): shutil.rmtree(dst)
    shutil.copytree(Path(snap) / k, dst, symlinks=False)
    size = sum(f.stat().st_size for f in dst.rglob("*") if f.is_file())
    log[k] = {"bytes": size, "files": sorted(p.name for p in dst.iterdir())}
    print(k, f"{size/1e6:.0f} MB", log[k]["files"])
for repo, name in TOK.items():
    p = snapshot_download(repo, allow_patterns=["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt",
                                                 "special_tokens_map.json", "added_tokens.json", "normalizer.json"])
    dst = out / name
    if dst.exists(): shutil.rmtree(dst)
    shutil.copytree(p, dst, symlinks=False)
    print(name, sorted(x.name for x in dst.iterdir()))
log["whisper_seconds"] = time.time() - t0
if "--skip-nllb" not in sys.argv:
    work = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "nllb287"
    subprocess.run([sys.executable, str(Path(__file__).with_name("convert_nllb287.py")), str(work)], check=True)
    nd = out / "nllb"; nd.mkdir(exist_ok=True)
    for m in ["NLLBEncoder", "NLLBDecoder"]:
        target = nd / f"{m}.mlmodelc"
        if target.exists(): shutil.rmtree(target)
        subprocess.run(["xcrun", "coremlcompiler", "compile", str(work / f"{m}.mlpackage"), str(nd)], check=True)
    for j in ["nllb287_vocab.json", "nllb287_reference.json"]: shutil.copy(work / j, nd / j)
    log["nllb_bytes"] = sum(f.stat().st_size for f in nd.rglob("*") if f.is_file())
    print("nllb", f"{log['nllb_bytes']/1e6:.0f} MB")
log["total_bytes"] = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
(out / "MODELS287.json").write_text(json.dumps(log, indent=2))
print(json.dumps({k: v for k, v in log.items() if not isinstance(v, dict)}, indent=2))
