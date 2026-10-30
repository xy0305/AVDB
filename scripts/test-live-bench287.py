#!/usr/bin/env python3
"""Build 287 CI bench: shipping live-subtitle sources + WhisperKit + NLLB Core ML + FFmpeg reader on the CI Mac.
Needs AVDB/Resources/LiveModels populated (fetch_models287.py). Writes evidence-live287/bench/*."""
import json, os, platform, shutil, subprocess, sys, time, socket
from pathlib import Path
r = Path(__file__).resolve().parents[1]
assert platform.system() == "Darwin"
out = r / "evidence-live287" / "bench"; out.mkdir(parents=True, exist_ok=True)
work = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "live287-bench"; work.mkdir(parents=True, exist_ok=True)
models = r / "AVDB/Resources/LiveModels"
subprocess.run([sys.executable, str(r / "scripts/live287/prepare_bench287.py"), str(work)], check=True)
src = r / "scripts/live287/bench/Sources/LiveBench287"
for f in ["LiveSubtitleCore.swift", "LiveAudioReader.swift", "LiveSpeechEngines.swift", "LiveAppleTranslation.swift"]:
    shutil.copy(r / "AVDB/Services" / f, src / f)
t0 = time.time()
subprocess.run(["swift", "build", "-c", "release", "--package-path", str(r / "scripts/live287/bench")], check=True)
build_s = time.time() - t0
binp = subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path", "--package-path", str(r / "scripts/live287/bench")], text=True).strip()
port = 8787
server = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"], cwd=work / "hls",
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(50):
    try: socket.create_connection(("127.0.0.1", port), 0.2).close(); break
    except OSError: time.sleep(0.1)
try:
    with open(out / "bench287.log", "w") as log:
        p = subprocess.Popen([os.path.join(binp, "LiveBench287"), str(models), str(work), f"http://127.0.0.1:{port}/index.m3u8"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in p.stdout:
            sys.stdout.write(line); log.write(line)
        code = p.wait()
finally:
    server.terminate()
for f in ["bench287.json", "timeline.json"]:
    if (work / f).exists(): shutil.copy(work / f, out / f)
if (models / "MODELS287.json").exists(): shutil.copy(models / "MODELS287.json", out / "MODELS287.json")
hw = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string", "hw.ncpu", "hw.memsize"], capture_output=True, text=True).stdout
(out / "host.txt").write_text(hw + f"swift build {build_s:.0f}s\n")
print("exit", code)
raise SystemExit(code)
