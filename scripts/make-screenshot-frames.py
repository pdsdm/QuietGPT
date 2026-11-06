import sys
from pathlib import Path

from PIL import Image, ImageDraw

SCREEN_WIDTH = 1206
SCREEN_HEIGHT = 2622
SCREEN_RADIUS = 186
BEZEL = 34
RIM = 14
BUTTON_DEPTH = 8
MARGIN = 14
OUTPUT_WIDTH = 720

ISLAND_WIDTH = 378
ISLAND_HEIGHT = 111
ISLAND_TOP = 33
LENS_RADIUS = 21


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def rim_fill(size):
    ramp = Image.linear_gradient("L").resize(size)
    return Image.composite(
        Image.new("RGBA", size, (58, 58, 62, 255)),
        Image.new("RGBA", size, (138, 138, 144, 255)),
        ramp,
    )


def framed(screenshot):
    screen = screenshot.convert("RGBA").resize((SCREEN_WIDTH, SCREEN_HEIGHT), Image.LANCZOS)
    inset = MARGIN + RIM + BEZEL
    size = (SCREEN_WIDTH + 2 * inset, SCREEN_HEIGHT + 2 * inset)
    right = size[0] - MARGIN - 1
    bottom = size[1] - MARGIN - 1
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    button = (92, 92, 97, 255)
    for top, height in ((430, 110), (610, 200), (850, 200)):
        draw.rounded_rectangle((MARGIN - BUTTON_DEPTH, top, MARGIN + 8, top + height), radius=5, fill=button)
    for top, height in ((720, 310), (1500, 170)):
        draw.rounded_rectangle((right - 8, top, right + BUTTON_DEPTH, top + height), radius=5, fill=button)

    body = (MARGIN, MARGIN, right, bottom)
    body_radius = SCREEN_RADIUS + BEZEL + RIM
    canvas.paste(rim_fill(size), (0, 0), rounded_mask(size, body, body_radius))

    bezel = (MARGIN + RIM, MARGIN + RIM, right - RIM, bottom - RIM)
    draw.rounded_rectangle(bezel, radius=SCREEN_RADIUS + BEZEL, fill=(0, 0, 0, 255))

    screen_size = (SCREEN_WIDTH, SCREEN_HEIGHT)
    screen_box = (0, 0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1)
    canvas.paste(screen, (inset, inset), rounded_mask(screen_size, screen_box, SCREEN_RADIUS))
    draw.rounded_rectangle(
        (inset - 3, inset - 3, inset + SCREEN_WIDTH + 2, inset + SCREEN_HEIGHT + 2),
        radius=SCREEN_RADIUS + 3,
        outline=(44, 44, 46, 255),
        width=3,
    )

    island_left = inset + (SCREEN_WIDTH - ISLAND_WIDTH) // 2
    island_top = inset + ISLAND_TOP
    draw.rounded_rectangle(
        (island_left, island_top, island_left + ISLAND_WIDTH, island_top + ISLAND_HEIGHT),
        radius=ISLAND_HEIGHT // 2,
        fill=(10, 10, 11, 255),
        outline=(72, 72, 76, 255),
        width=3,
    )
    lens_x = island_left + ISLAND_WIDTH - ISLAND_HEIGHT // 2
    lens_y = island_top + ISLAND_HEIGHT // 2
    draw.ellipse(
        (lens_x - LENS_RADIUS, lens_y - LENS_RADIUS, lens_x + LENS_RADIUS, lens_y + LENS_RADIUS),
        fill=(24, 28, 44, 255),
        outline=(52, 56, 72, 255),
        width=3,
    )

    output_height = round(size[1] * OUTPUT_WIDTH / size[0])
    return canvas.resize((OUTPUT_WIDTH, output_height), Image.LANCZOS)


def main():
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob("*.png")):
        framed(Image.open(path)).save(destination / path.name, optimize=True)


if __name__ == "__main__":
    main()
