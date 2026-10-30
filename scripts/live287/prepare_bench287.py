#!/usr/bin/env python3
"""Build 287 bench input (CI Mac): Japanese speech from macOS TTS (ja_JP voice, e.g. Kyoko) for the CC0 lines in
ja_samples287.py → per-line 16 kHz PCM + one program track with pauses → muxed HLS (H.264 test pattern + AAC
44.1 kHz stereo, 2 s segments) so the reader has to discard video like a real online/115 stream.
Usage: prepare_bench287.py WORK_DIR"""
import json, re, struct, subprocess, sys, random
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from ja_samples287 import SENTENCES

work = Path(sys.argv[1]); work.mkdir(parents=True, exist_ok=True)
voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout.splitlines()
ja = [re.split(r"\s{2,}", v.strip())[0] for v in voices if "ja_JP" in v]
voice = next((v for v in ja if v.startswith("Kyoko")), ja[0] if ja else None)
assert voice, "no ja_JP voice installed: " + "\n".join(voices[:40])
print("voice", voice)
RATE = 16000
pcm = bytearray()
def silence(sec, noise=True):
    rnd = random.Random(len(pcm))
    return b"".join(struct.pack("<h", int(rnd.gauss(0, 30)) if noise else 0) for _ in range(int(sec * RATE)))
pcm += silence(1.5)
timeline = []
for i, s in enumerate(SENTENCES):
    aiff = work / f"line{i}.aiff"; raw = work / f"line{i}.raw"
    subprocess.run(["say", "-v", voice, "-r", "190", "-o", str(aiff), s["ja"]], check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(aiff), "-ar", str(RATE), "-ac", "1", "-f", "s16le", str(raw)], check=True)
    data = raw.read_bytes()
    start = len(pcm) / 2 / RATE
    pcm += data
    end = len(pcm) / 2 / RATE
    timeline.append({"ja": s["ja"], "zh": s["zh"], "start": round(start, 3), "end": round(end, 3), "raw": raw.name})
    pcm += silence(1.1 if i % 3 else 1.6)
pcm += silence(2.0)
(work / "program.raw").write_bytes(pcm)
(work / "timeline.json").write_text(json.dumps(timeline, ensure_ascii=False, indent=1))
hls = work / "hls"; hls.mkdir(exist_ok=True)
dur = len(pcm) / 2 / RATE
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", str(work / "program.raw"),
                "-f", "lavfi", "-i", f"testsrc2=size=640x360:rate=25:duration={dur:.2f}",
                "-map", "1:v", "-map", "0:a", "-c:v", "libx264", "-preset", "veryfast", "-g", "50", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-ar", "44100", "-ac", "2", "-b:a", "128k", "-shortest",
                "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod", "-hls_segment_filename", str(hls / "seg%03d.ts"), str(hls / "index.m3u8")], check=True)
print(json.dumps({"voice": voice, "duration_s": round(dur, 2), "lines": len(timeline), "segments": len(list(hls.glob('*.ts')))}, ensure_ascii=False))
