import sys

TONES = {"1F3FB", "1F3FC", "1F3FD", "1F3FE", "1F3FF"}
SECTIONS = [
    ("Smileys & People", "face.smiling"),
    ("Animals & Nature", "pawprint"),
    ("Food & Drink", "fork.knife"),
    ("Activity", "basketball"),
    ("Travel & Places", "car"),
    ("Objects", "lightbulb"),
    ("Symbols", "number"),
    ("Flags", "flag"),
]
GROUPS = {
    "Smileys & Emotion": "Smileys & People",
    "People & Body": "Smileys & People",
    "Animals & Nature": "Animals & Nature",
    "Food & Drink": "Food & Drink",
    "Activities": "Activity",
    "Travel & Places": "Travel & Places",
    "Objects": "Objects",
    "Symbols": "Symbols",
    "Flags": "Flags",
}
MOVED = {"heart": "Symbols", "clothing": "Smileys & People"}


def glyph(codes):
    return "".join(chr(int(code, 16)) for code in codes)


def read(path):
    items = {title: [] for title, _ in SECTIONS}
    moved = {title: [] for title, _ in SECTIONS}
    bases = {}
    group = subgroup = None
    for line in open(path, encoding="utf-8"):
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
        elif line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
        elif "; fully-qualified" in line and group in GROUPS:
            codes = line.split(";")[0].split()
            tones = [code for code in codes if code in TONES]
            plain = tuple(code for code in codes if code not in TONES and code != "FE0F")
            if tones:
                if len(set(tones)) == 1 and plain in bases:
                    bases[plain]["tones"].append(glyph(codes))
                continue
            item = {"text": glyph(codes), "tones": []}
            bases[plain] = item
            if subgroup in MOVED:
                moved[MOVED[subgroup]].append(item)
            else:
                items[GROUPS[group]].append(item)
    for title in items:
        items[title] = moved[title] + items[title] if title == "Symbols" else items[title] + moved[title]
    return items


def entry(item):
    tones = item["tones"] if len(item["tones"]) == 5 else []
    return "|".join([item["text"]] + tones)


def main():
    source, target = sys.argv[1], sys.argv[2]
    items = read(source)
    with open(target, "w", encoding="utf-8") as out:
        out.write("enum EmojiData {\n")
        out.write("    static let sections: [(title: String, symbol: String, text: String)] = [\n")
        for index, (title, symbol) in enumerate(SECTIONS):
            text = " ".join(entry(item) for item in items[title])
            comma = "," if index < len(SECTIONS) - 1 else ""
            out.write(f'        ("{title}", "{symbol}", "{text}"){comma}\n')
        out.write("    ]\n}\n")
    for title, _ in SECTIONS:
        toned = sum(1 for item in items[title] if len(item["tones"]) == 5)
        print(title, len(items[title]), "with tones:", toned)
    print("total", sum(len(value) for value in items.values()))


main()
