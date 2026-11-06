import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "Rewrite/Fonts/Geist-SemiBold.ttf"

CANVAS = (1320, 2868)
PHONE_WIDTH = 1060
BOTTOM_MARGIN = 96
CAPTION_TOP = 150
CAPTION_MAX_WIDTH = 1180
CAPTION_SIZE = 104
LINE_GAP = 22
TOP_COLOR = 26
BOTTOM_COLOR = 0

SHOTS = ["panel", "letters", "rules", "chat", "privacy", "onboarding"]

CAPTIONS = {
    "en": {
        "panel": "Rewrite any message\nin one tap",
        "letters": "A full keyboard\nin any app",
        "rules": "Your rules.\nYour people.",
        "chat": "A private chat\non your iPhone",
        "privacy": "No account. No server.\nYou can check it.",
        "onboarding": "Free and open source\nMIT License",
    },
    "es": {
        "panel": "Reescribe cualquier\nmensaje con un toque",
        "letters": "Un teclado completo\nen cualquier app",
        "rules": "Tus reglas.\nTus personas.",
        "chat": "Un chat privado\nen tu iPhone",
        "privacy": "Sin cuentas ni servidores.\nCompruébalo tú.",
        "onboarding": "Gratis y de código abierto\nLicencia MIT",
    },
}


def load_frames():
    spec = importlib.util.spec_from_file_location("frames", ROOT / "scripts/make-screenshot-frames.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.OUTPUT_WIDTH = PHONE_WIDTH
    return module


def background():
    ramp = Image.linear_gradient("L").resize(CANVAS)
    top = Image.new("RGB", CANVAS, (TOP_COLOR, TOP_COLOR, TOP_COLOR + 2))
    bottom = Image.new("RGB", CANVAS, (BOTTOM_COLOR, BOTTOM_COLOR, BOTTOM_COLOR))
    return Image.composite(bottom, top, ramp)


def caption_font(text):
    size = CAPTION_SIZE
    while True:
        font = ImageFont.truetype(str(FONT), size)
        widest = max(font.getlength(line) for line in text.split("\n"))
        if widest <= CAPTION_MAX_WIDTH:
            return font
        size -= 2


def compose(raw, caption, frames):
    canvas = background()
    phone = frames.framed(raw)
    left = (CANVAS[0] - phone.width) // 2
    canvas.paste(phone, (left, CANVAS[1] - phone.height - BOTTOM_MARGIN), phone)

    draw = ImageDraw.Draw(canvas)
    font = caption_font(caption)
    draw.multiline_text(
        (CANVAS[0] / 2, CAPTION_TOP),
        caption,
        font=font,
        fill=(255, 255, 255),
        anchor="ma",
        align="center",
        spacing=LINE_GAP,
    )
    return canvas


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in CAPTIONS:
        print("Usage: make-store-screenshots.py <raw folder> <en|es> <output folder>")
        sys.exit(1)
    source = Path(sys.argv[1])
    language = sys.argv[2]
    destination = Path(sys.argv[3])
    destination.mkdir(parents=True, exist_ok=True)
    frames = load_frames()
    for number, name in enumerate(SHOTS, start=1):
        image = compose(Image.open(source / f"{name}.png"), CAPTIONS[language][name], frames)
        image.save(destination / f"{number:02d}-{name}.png", optimize=True)


if __name__ == "__main__":
    main()
