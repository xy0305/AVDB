#!/usr/bin/env python3
"""Build 289 CI bench: SenseVoice (sherpa-onnx) vs Whisper small vs Apple on-device recognition, shipping sources, CI Mac.
Needs AVDB/Resources/LiveModels (fetch_models287.py + fetch_live289.py) and Vendor/sherpa-onnx-macos.xcframework.
Writes evidence-live289/bench/*."""
import json, os, platform, shutil, subprocess, sys, time, socket
from pathlib import Path
r = Path(__file__).resolve().parents[1]
assert platform.system() == "Darwin"
out = r / "evidence-live289" / "bench"; out.mkdir(parents=True, exist_ok=True)
work = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "live289-bench"; work.mkdir(parents=True, exist_ok=True)
models = r / "AVDB/Resources/LiveModels"
subprocess.run([sys.executable, str(r / "scripts/live287/prepare_bench287.py"), str(work)], check=True)
src = r / "scripts/live289/bench/Sources/LiveBench289"
lib = r / "Vendor/sherpa-onnx-macos.xcframework/macos-arm64_x86_64"
(r / "scripts/live289/bench/Sources/SherpaOnnxC").mkdir(parents=True, exist_ok=True)
(r / "scripts/live289/bench/Sources/SherpaOnnxC/module.modulemap").write_text(
    'module SherpaOnnxC {\n  header "%s"\n  link "sherpa-onnx-c-api"\n  export *\n}\n' % (lib / "Headers/sherpa-onnx/c-api/c-api.h"))
for f in ["LiveSubtitleCore.swift", "LiveTranslationPrep.swift", "LiveAudioReader.swift", "LiveSpeechEngines.swift", "LiveAppleTranslation.swift", "LiveSenseVoice.swift", "LiveSystemRecognizers.swift"]:
    shutil.copy(r / "AVDB/Services" / f, src / f)
t0 = time.time()
flags = ["-Xlinker", "-L" + str(lib), "-Xlinker", "-rpath", "-Xlinker", str(lib)]
subprocess.run(["swift", "build", "-c", "release", "--package-path", str(r / "scripts/live289/bench")] + flags, check=True)
build_s = time.time() - t0
binp = subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path", "--package-path", str(r / "scripts/live289/bench")] + flags, text=True).strip()
port = 8787
server = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"], cwd=work / "hls",
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(50):
    try: socket.create_connection(("127.0.0.1", port), 0.2).close(); break
    except OSError: time.sleep(0.1)
try:
    with open(out / "bench289.log", "w") as log:
        p = subprocess.Popen([os.path.join(binp, "LiveBench289"), str(models), str(work), f"http://127.0.0.1:{port}/index.m3u8"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in p.stdout:
            sys.stdout.write(line); log.write(line)
        code = p.wait()
finally:
    server.terminate()
for f in ["bench289.json", "timeline.json"]:
    if (work / f).exists(): shutil.copy(work / f, out / f)
for m in ["MODELS287.json", "MODELS289.json"]:
    if (models / m).exists(): shutil.copy(models / m, out / m)
hw = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string", "hw.ncpu", "hw.memsize"], capture_output=True, text=True).stdout
(out / "host.txt").write_text(hw + f"swift build {build_s:.0f}s\n")
print("exit", code)
raise SystemExit(code)
