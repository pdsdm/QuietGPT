import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import header

PROMO = header.PROMO
SOURCE = PROMO / "footage" / "device" / "offline_chat.mov"
WORK = PROMO / "build" / "header-video"
SCREENS = WORK / "screen"
PHONES = WORK / "phone"
OUT = header.OUT
FPS = 30
START, END = 7.0, 13.0
SKIP = (12.145, 12.49)
HOLD = 2.0
ISLAND_COVER = (0.28, 0.71, 0.01, 0.056)
VIDEOS = ("header", "search")


def run(cmd):
    subprocess.run(cmd, check=True)


def screens():
    shutil.rmtree(SCREENS, ignore_errors=True)
    SCREENS.mkdir(parents=True)
    w, h = 1320, 2868
    x0, x1, y0, y1 = (round(v * s) for v, s in zip(ISLAND_COVER, (w, w, h, h)))
    pill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle((x0, y0, x1, y1), radius=(y1 - y0) // 2, fill=(0, 0, 0, 255))
    pill_path = WORK / "pill.png"
    pill.save(pill_path)
    a, b = SKIP
    vf = (f"[0:v][1:v]overlay=0:0,"
          f"select='not(between(t\\,{a - START:.4f}\\,{b - START:.4f}))',setpts=N/FRAME_RATE/TB,fps={FPS},"
          f"tpad=stop_mode=clone:stop_duration={HOLD}")
    run(["ffmpeg", "-v", "error", "-y", "-ss", f"{START}", "-t", f"{END - START}", "-i", str(SOURCE), "-i", str(pill_path),
         "-filter_complex", vf, str(SCREENS / "%04d.png")])
    return sorted(SCREENS.glob("*.png"))


def phones(frames):
    shutil.rmtree(PHONES, ignore_errors=True)
    PHONES.mkdir(parents=True)
    header.render_phones([{"screen": str(f.relative_to(PROMO)), "out": str((PHONES / f.name).relative_to(PROMO))}
                          for f in frames])
    return [PHONES / f.name for f in frames]


def encode(lang, phone_paths):
    layouts = {name: header.Layout(name, lang) for name in VIDEOS}
    procs = {}
    for name, lay in layouts.items():
        procs[name] = subprocess.Popen([
            "ffmpeg", "-v", "error", "-y",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{lay.w}x{lay.h}", "-r", str(FPS), "-i", "-",
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-shortest", "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-crf", "16",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
            str(OUT / f"{name}-{lang}.mp4"),
        ], stdin=subprocess.PIPE)
    for p in phone_paths:
        phone = Image.open(p).convert("RGBA")
        for name, lay in layouts.items():
            procs[name].stdin.write(lay.frame(phone).tobytes())
    for name, proc in procs.items():
        proc.stdin.close()
        proc.wait()
        print(OUT / f"{name}-{lang}.mp4")


def main():
    phone_paths = sorted(PHONES.glob("*.png")) if "--reuse" in sys.argv else phones(screens())
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in header.TEXT:
        encode(lang, phone_paths)


if __name__ == "__main__":
    main()
