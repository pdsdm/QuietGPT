import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROMO = Path(__file__).resolve().parent.parent
REPO = PROMO.parent
RAW = PROMO / "build" / "store-raw"
RENDER = PROMO / "build" / "store-3d" / "header-phone.png"
ICON = REPO / "QuietGPT" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"
OUT = PROMO / "store" / "header"

W, H = 5244, 2950
BG = (255, 255, 255)
INK = (17, 17, 19)
GRAY = (120, 120, 126)
SF = "/System/Library/Fonts/SFNS.ttf"
PHONE_H = 2700
PHONE_W = 1480
LEFT = 420

TEXT = {
    "en": {
        "title": ["Private AI.", "On your iPhone."],
        "body": ["No server. No account.", "Works in Airplane Mode."],
        "chips": ["Offline", "Neural Engine", "Open source"],
    },
    "es": {
        "title": ["IA privada.", "En tu iPhone."],
        "body": ["Sin servidor. Sin cuentas.", "Funciona en modo avión."],
        "chips": ["Sin conexión", "Neural Engine", "Código abierto"],
    },
}


def font(size, weight="Semibold"):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def render_phone():
    job = [{
        "screen": str((RAW / "reply.png").relative_to(PROMO)),
        "out": str(RENDER.relative_to(PROMO)),
        "width": PHONE_W,
        "height": PHONE_H,
        "yaw": -16,
        "tilt": 4,
        "roll": 2,
        "fill": 0.97,
        "island": True,
    }]
    path = PROMO / "build" / "store-header-job.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(job))
    subprocess.run(["node", str(PROMO / "render3d" / "still.mjs"), str(path)], check=True, cwd=PROMO)


def rounded_icon(size):
    icon = Image.open(ICON).convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * 0.225), fill=255)
    return icon, mask.resize((size, size), Image.LANCZOS)


def compose(lang):
    t = TEXT[lang]
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)

    icon_size = 420
    icon, mask = rounded_icon(icon_size)
    top = 330
    canvas.paste(icon, (LEFT, top), mask)
    d.text((LEFT + icon_size + 90, top + icon_size / 2), "QuietGPT", font=font(240, "Bold"), fill=INK, anchor="lm")

    y = top + icon_size + 380
    title_font = font(330, "Bold")
    for line in t["title"]:
        d.text((LEFT - 12, y), line, font=title_font, fill=INK, anchor="ls")
        y += 380

    y += 60
    body_font = font(130, "Medium")
    for line in t["body"]:
        d.text((LEFT, y), line, font=body_font, fill=GRAY, anchor="ls")
        y += 175

    y += 120
    chip_font = font(96, "Semibold")
    x = LEFT
    for chip in t["chips"]:
        w = d.textlength(chip, font=chip_font) + 140
        d.rounded_rectangle((x, y, x + w, y + 190), radius=95, fill=(242, 242, 244))
        d.text((x + w / 2, y + 95), chip, font=chip_font, fill=INK, anchor="mm")
        x += w + 50

    phone = Image.open(RENDER).convert("RGBA")
    px = W - PHONE_W - 520
    py = (H - PHONE_H) // 2
    shade = phone.getchannel("A").point(lambda a: a * 0.32).filter(ImageFilter.GaussianBlur(60))
    canvas.paste(Image.new("RGB", phone.size, (0, 0, 0)), (px, py + 60), shade)
    canvas.paste(phone, (px, py), phone)
    return canvas


def main():
    render_phone()
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in TEXT:
        path = OUT / f"header-{lang}.png"
        compose(lang).save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
