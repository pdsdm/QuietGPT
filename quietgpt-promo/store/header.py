import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROMO = Path(__file__).resolve().parent.parent
RAW = PROMO / "build" / "store-raw"
RENDER = PROMO / "build" / "store-3d" / "header-phone.png"
OUT = PROMO / "store" / "header"

BG = (255, 255, 255)
INK = (17, 17, 19)
GRAY = (120, 120, 126)
CHIP = (242, 242, 244)
SF = "/System/Library/Fonts/SFNS.ttf"
PHONE_W, PHONE_H = 1200, 2200
POSE = {"yaw": -16, "tilt": 4, "roll": 2, "fill": 0.97, "island": True}

SPECS = {
    "header": {"size": (3840, 1646), "safe": 0.58, "band": (0.13, 0.95), "body": 1, "chips": False, "drop": 0.07},
    "search": {"size": (3840, 2560), "safe": 0.9, "band": (0.07, 0.95), "body": 2, "chips": True, "drop": 0.0},
    "universal": {"size": (5244, 2950), "safe": 0.47, "band": (0.14, 0.86), "body": 1, "chips": False, "drop": 0.1},
}

TEXT = {
    "en": {
        "title": ["Private AI.", "On your iPhone."],
        "body": ["No server. No account.", "Works in Airplane Mode."],
        "short": "No server. Works offline.",
        "chips": ["Offline", "Neural Engine", "Open source"],
    },
    "es": {
        "title": ["IA privada.", "En tu iPhone."],
        "body": ["Sin servidor. Sin cuentas.", "Funciona en modo avión."],
        "short": "Sin servidor. Sin conexión.",
        "chips": ["Sin conexión", "Neural Engine", "Código abierto"],
    },
}


def font(size, weight="Semibold"):
    f = ImageFont.truetype(SF, round(size))
    f.set_variation_by_name(weight)
    return f


def render_phones(jobs):
    path = PROMO / "build" / "store-header-jobs.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([{**POSE, **j, "width": PHONE_W, "height": PHONE_H} for j in jobs]))
    subprocess.run(["node", str(PROMO / "promo-39s" / "render3d" / "still.mjs"), str(path)], check=True, cwd=PROMO,
                   stdout=subprocess.DEVNULL)


class Layout:
    def __init__(self, spec_name, lang):
        spec = SPECS[spec_name]
        self.w, self.h = spec["size"]
        t = TEXT[lang]
        safe_w = self.w * spec["safe"]
        x0 = (self.w - safe_w) / 2
        x1 = x0 + safe_w
        y0, y1 = (self.h * f for f in spec["band"])
        band = y1 - y0

        self.ph = round(band)
        self.pw = round(self.ph * PHONE_W / PHONE_H)
        self.px = round(x1 - self.pw)
        self.py = round(y0)

        text_w = self.px - x0 - band * 0.05
        lines = t["title"]
        body = t["body"] if spec["body"] == 2 else [t["short"]]
        probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
        size = band * 0.2
        while max(probe.textlength(l, font=font(size, "Bold")) for v in TEXT.values() for l in v["title"]) > text_w:
            size -= 2
        body_size = size * 0.4
        chip_size = size * 0.3
        while sum(probe.textlength(c, font=font(chip_size)) + chip_size * 1.9 for c in t["chips"]) > text_w:
            chip_size -= 1
        title_lh, body_lh = size * 1.12, body_size * 1.35
        block = title_lh * len(lines) + size * 0.35 + body_lh * len(body)
        if spec["chips"]:
            block += size * 0.45 + chip_size * 2
        y = y0 + (band - block) / 2 + size * 0.9 + self.h * spec["drop"]

        self.base = Image.new("RGB", (self.w, self.h), BG)
        d = ImageDraw.Draw(self.base)
        for line in lines:
            d.text((x0 - size * 0.04, y), line, font=font(size, "Bold"), fill=INK, anchor="ls")
            y += title_lh
        y += size * 0.35 - title_lh + body_lh
        for line in body:
            d.text((x0, y), line, font=font(body_size, "Medium"), fill=GRAY, anchor="ls")
            y += body_lh
        if spec["chips"]:
            y += size * 0.45 - body_lh * 0.6
            cf = font(chip_size)
            ch = chip_size * 2
            x = x0
            for chip in t["chips"]:
                cw = d.textlength(chip, font=cf) + chip_size * 1.4
                d.rounded_rectangle((x, y, x + cw, y + ch), radius=ch / 2, fill=CHIP)
                d.text((x + cw / 2, y + ch / 2), chip, font=cf, fill=INK, anchor="mm")
                x += cw + chip_size * 0.5
        self.shade = None

    def frame(self, phone):
        phone = phone.resize((self.pw, self.ph), Image.LANCZOS)
        if self.shade is None:
            blur = self.ph * 0.022
            self.shade = phone.getchannel("A").point(lambda a: a * 0.32).filter(ImageFilter.GaussianBlur(blur))
        canvas = self.base.copy()
        canvas.paste(Image.new("RGB", phone.size, (0, 0, 0)), (self.px, self.py + round(self.ph * 0.022)), self.shade)
        canvas.paste(phone, (self.px, self.py), phone)
        return canvas


def main():
    render_phones([{"screen": str((RAW / "reply.png").relative_to(PROMO)), "out": str(RENDER.relative_to(PROMO))}])
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    phone = Image.open(RENDER).convert("RGBA")
    for lang in TEXT:
        path = OUT / f"universal-{lang}.png"
        Layout("universal", lang).frame(phone).save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
